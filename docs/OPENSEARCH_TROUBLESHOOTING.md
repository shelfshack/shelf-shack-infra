# OpenSearch EC2 Troubleshooting Guide

## Connection Refused Error

If you see errors like:
```
ConnectionError: Connection refused (Errno 111)
```

This means the OpenSearch service isn't running or isn't accessible on the EC2 instance.

## Quick Diagnosis

### 1. Check EC2 Instance Status

```bash
cd envs/dev

# Get instance ID
INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id)
echo "Instance ID: $INSTANCE_ID"

# Check instance state
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].[State.Name,PrivateIpAddress,LaunchTime]' \
  --output table
```

### 2. Check User Data Execution

```bash
# Connect via SSM
aws ssm start-session --target $INSTANCE_ID

# Once connected, check user data logs
sudo cat /var/log/user-data.log
sudo cat /var/log/cloud-init-output.log
```

### 3. Check Docker and OpenSearch Container

```bash
# Connect via SSM
aws ssm start-session --target $INSTANCE_ID

# Check if Docker is running
sudo systemctl status docker

# Check if OpenSearch container is running
sudo docker ps -a

# Check OpenSearch container logs
sudo docker logs opensearch

# Check if OpenSearch is listening on port 9200
sudo netstat -tlnp | grep 9200
# or
sudo ss -tlnp | grep 9200
```

### 4. Test OpenSearch from EC2 Instance

```bash
# Connect via SSM
aws ssm start-session --target $INSTANCE_ID

# Test local connection
curl http://localhost:9200/_cluster/health

# Check OpenSearch info
curl http://localhost:9200/
```

### 5. Check Security Groups

```bash
# Get security group ID
SG_ID=$(terraform output -raw opensearch_ec2_security_group_id 2>/dev/null || \
  aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
    --output text)

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json | python3 -m json.tool
```

## Common Issues and Solutions

### Issue 1: Docker Not Installed or Not Running

**Symptoms:**
- `sudo docker ps` fails
- Container not found

**Solution:**
```bash
# Connect via SSM and manually install/start Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
```

### Issue 2: OpenSearch Container Not Running

**Symptoms:**
- `sudo docker ps` shows no opensearch container
- Container exists but is stopped

**Solution:**
```bash
# Check container status
sudo docker ps -a | grep opensearch

# If container exists but stopped, start it
sudo docker start opensearch

# If container doesn't exist, create it manually
sudo docker run -d \
  --name opensearch \
  --restart unless-stopped \
  -p 9200:9200 \
  -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m" \
  -e "plugins.security.disabled=true" \
  -v opensearch-data:/usr/share/opensearch/data \
  opensearchproject/opensearch:latest
```

### Issue 3: OpenSearch Container Crashed

**Symptoms:**
- Container exists but status is "Exited"
- Container logs show errors

**Solution:**
```bash
# Check container logs
sudo docker logs opensearch

# Common issues:
# - Out of memory: Reduce heap size or upgrade instance
# - Port conflict: Check if port 9200 is already in use
# - Disk space: Check available disk space

# Restart container
sudo docker restart opensearch

# Or recreate with different settings
sudo docker rm opensearch
# Then run the docker run command from Issue 2
```

### Issue 4: OpenSearch Not Listening on Port 9200

**Symptoms:**
- Container is running
- `curl http://localhost:9200` fails
- `netstat` shows port 9200 not listening

**Solution:**
```bash
# Check container logs for startup errors
sudo docker logs opensearch --tail 50

# Check if OpenSearch is still starting (can take 1-2 minutes)
# Wait and retry:
for i in {1..30}; do
  if curl -sf http://localhost:9200/_cluster/health; then
    echo "OpenSearch is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 5
done
```

### Issue 5: Security Group Not Allowing Connection

**Symptoms:**
- OpenSearch works from EC2 instance (localhost)
- Connection fails from ECS service
- Connection timeout (not connection refused)

**Solution:**
```bash
# Verify security group rules
# Should allow port 9200 from ECS service security group
terraform output opensearch_ec2_security_group_id

# Check if rule exists
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$(terraform output -raw opensearch_ec2_security_group_id)" \
  --query 'SecurityGroupRules[?FromPort==`9200`]' \
  --output table
```

### Issue 6: User Data Script Failed

**Symptoms:**
- `/var/log/user-data.log` shows errors
- Docker/OpenSearch not installed

**Solution:**
```bash
# Check user data logs
sudo cat /var/log/user-data.log
sudo cat /var/log/cloud-init-output.log

# If user data failed, you can manually run the setup:
# (Copy the commands from modules/opensearch_ec2/main.tf user_data section)
```

## Manual Recovery Steps

If OpenSearch isn't working, you can manually set it up:

```bash
# 1. Connect to EC2 instance
aws ssm start-session --target $(terraform output -raw opensearch_ec2_instance_id)

# 2. Install Docker (if not installed)
sudo yum install -y docker curl
sudo systemctl start docker
sudo systemctl enable docker

# 3. Remove existing container (if any)
sudo docker stop opensearch 2>/dev/null || true
sudo docker rm opensearch 2>/dev/null || true

# 4. Start OpenSearch container
sudo docker run -d \
  --name opensearch \
  --restart unless-stopped \
  -p 9200:9200 \
  -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m" \
  -e "plugins.security.disabled=true" \
  -v opensearch-data:/usr/share/opensearch/data \
  opensearchproject/opensearch:latest

# 5. Wait for OpenSearch to start (1-2 minutes)
for i in {1..30}; do
  if curl -sf http://localhost:9200/_cluster/health; then
    echo "OpenSearch is ready!"
    curl http://localhost:9200/_cluster/health
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 5
done

# 6. Verify it's working
curl http://localhost:9200/
```

## Re-run User Data Script

If you need to re-run the user data script:

```bash
# Note: You cannot re-run user data on an existing instance
# You need to either:
# 1. Terminate and recreate the instance
# 2. Manually run the commands (see Manual Recovery Steps above)
```

## Verify from ECS Service

Once OpenSearch is running on EC2, verify connection from ECS:

```bash
# Get ECS task ID
TASK_ID=$(aws ecs list-tasks \
  --cluster $(terraform output -raw cluster_name) \
  --service-name $(terraform output -raw service_name) \
  --query 'taskArns[0]' \
  --output text | cut -d/ -f3)

# Execute command in ECS task
aws ecs execute-command \
  --cluster $(terraform output -raw cluster_name) \
  --task $TASK_ID \
  --container $(terraform output -raw service_name) \
  --interactive \
  --command "/bin/bash"

# From inside the container, test OpenSearch connection
OPENSEARCH_HOST=$(echo $OPENSEARCH_HOST)  # Should be the EC2 private IP
curl http://$OPENSEARCH_HOST:9200/_cluster/health
```

## Prevention

To prevent this issue in the future:

1. **Monitor CloudWatch Logs**: Set up CloudWatch agent on EC2 to monitor Docker/OpenSearch
2. **Health Checks**: Add a health check endpoint that ECS can use
3. **Auto-restart**: The `--restart unless-stopped` flag should auto-restart the container
4. **Instance Monitoring**: Monitor EC2 instance metrics (CPU, memory, disk)

## Getting Help

If issues persist:

1. Check all logs: `/var/log/user-data.log`, `/var/log/cloud-init-output.log`, `docker logs opensearch`
2. Verify instance has enough resources (t3.micro might be too small for OpenSearch)
3. Check AWS service health dashboard
4. Consider upgrading to a larger instance type if memory issues persist



