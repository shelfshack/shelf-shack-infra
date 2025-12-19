# OpenSearch on EC2 Setup

## Overview

OpenSearch is now deployed on an EC2 instance instead of as an ECS service. This approach provides:
- **Simpler architecture**: Single EC2 instance running OpenSearch in Docker
- **Cost-effective**: Uses t3.micro instance (free tier eligible)
- **Direct connection**: ECS FastAPI service connects directly to EC2 private IP
- **Easy management**: Standard EC2 instance with Docker container

## Architecture

```
EC2 (t3.micro)
 └── Docker
      └── OpenSearch (single-node)
           ├── Port 9200 (HTTP API)
           └── Port 9600 (Performance Analyzer)

ECS FastAPI Service
 └── Connects to EC2 private IP:9200
```

## Infrastructure Components

### Module: `opensearch_ec2`

Located at `modules/opensearch_ec2/`, this module creates:

1. **EC2 Instance** (t3.micro by default)
   - Amazon Linux 2023 AMI
   - Deployed in private subnet
   - IAM role with SSM access for remote management

2. **Security Group**
   - Allows port 9200 (OpenSearch HTTP) from ECS service security group
   - Allows port 9600 (Performance Analyzer) from ECS service security group
   - Optional: Allows SSH (port 22) from bastion host if enabled

3. **User Data Script**
   - Installs Docker
   - Starts Docker service
   - Runs OpenSearch container with single-node configuration
   - Disables security plugins for simplicity

4. **OpenSearch Container**
   - Image: `opensearchproject/opensearch:latest` (configurable)
   - Single-node discovery mode
   - Java heap size: 512m (configurable)
   - Data persisted in Docker volume

## Configuration

### Variables

In `envs/dev/terraform.tfvars` or via environment variables:

```hcl
# Enable OpenSearch on EC2 (default: true)
enable_opensearch_ec2 = true

# EC2 instance type (default: t3.micro)
opensearch_ec2_instance_type = "t3.micro"

# OpenSearch Docker image (default: opensearchproject/opensearch)
opensearch_ec2_image = "opensearchproject/opensearch"

# OpenSearch version/tag (default: latest)
opensearch_ec2_version = "latest"

# Java heap size (default: 512m)
opensearch_ec2_java_heap_size = "512m"
```

### Automatic Configuration

The ECS FastAPI service is automatically configured with:
- `OPENSEARCH_HOST` environment variable set to the EC2 private IP
- Security group rules allowing connection from ECS to EC2

## Connection Details

### From ECS FastAPI Service

The FastAPI service connects to OpenSearch using:
- **Host**: EC2 private IP (automatically set in `OPENSEARCH_HOST` env var)
- **Port**: 9200
- **Protocol**: HTTP (no SSL)
- **URL**: `http://<ec2-private-ip>:9200`

### From Your Local Machine

To access OpenSearch from your local machine:

1. **Via Bastion Host** (if enabled):
   ```bash
   # Port forward through bastion
   aws ssm start-session \
     --target $(terraform output -raw opensearch_ec2_instance_id) \
     --document-name AWS-StartPortForwardingSession \
     --parameters '{"portNumber":["9200"],"localPortNumber":["19200"]}'
   
   # Access at http://localhost:19200
   ```

2. **Via ECS Exec** (if enabled):
   ```bash
   # Connect to ECS task
   aws ecs execute-command \
     --cluster <cluster-name> \
     --task <task-id> \
     --container <container-name> \
     --interactive \
     --command "/bin/bash"
   
   # From inside the container, curl OpenSearch
   curl http://<ec2-private-ip>:9200/_cluster/health
   ```

## Health Checks

### Check OpenSearch Status

```bash
# From ECS task or via port forwarding
curl http://<ec2-private-ip>:9200/_cluster/health
```

Expected response:
```json
{
  "cluster_name": "docker-cluster",
  "status": "green",
  "timed_out": false,
  "number_of_nodes": 1,
  "number_of_data_nodes": 1,
  "active_primary_shards": 0,
  "active_shards": 0,
  "relocating_shards": 0,
  "initializing_shards": 0,
  "unassigned_shards": 0,
  "delayed_unassigned_shards": 0,
  "number_of_pending_tasks": 0,
  "number_of_in_flight_fetch": 0,
  "task_max_waiting_in_queue_millis": 0,
  "active_shards_percent_as_number": 100.0
}
```

### Check EC2 Instance Status

```bash
# Get instance ID
terraform output opensearch_ec2_instance_id

# Check instance status
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].State.Name'
```

## Troubleshooting

### OpenSearch Not Starting

1. **Check EC2 instance logs**:
   ```bash
   aws ssm start-session --target <instance-id>
   sudo journalctl -u docker -f
   ```

2. **Check Docker container**:
   ```bash
   sudo docker ps -a
   sudo docker logs opensearch
   ```

3. **Check user data script**:
   ```bash
   sudo cat /var/log/cloud-init-output.log
   ```

### ECS Cannot Connect to OpenSearch

1. **Verify security group rules**:
   - EC2 security group should allow port 9200 from ECS security group
   - Check both security groups exist and are correctly configured

2. **Verify network connectivity**:
   - Both ECS and EC2 should be in the same VPC
   - Check subnet routing

3. **Check OpenSearch is listening**:
   ```bash
   # On EC2 instance
   sudo netstat -tlnp | grep 9200
   ```

### Performance Issues

If OpenSearch is slow or running out of memory:

1. **Increase Java heap size**:
   ```hcl
   opensearch_ec2_java_heap_size = "1g"
   ```

2. **Upgrade instance type**:
   ```hcl
   opensearch_ec2_instance_type = "t3.small"
   ```

3. **Monitor CloudWatch metrics**:
   - CPU utilization
   - Memory utilization
   - Network I/O

## Migration from ECS-based OpenSearch

If you were previously using the ECS-based OpenSearch:

1. **The old modules are still available** but commented out in `envs/dev/main.tf`
2. **Data migration**: If you have existing OpenSearch data, you'll need to:
   - Export data from old OpenSearch
   - Import into new EC2-based OpenSearch
   - Or start fresh (data will be re-indexed)

3. **Update application**: No changes needed - the `OPENSEARCH_HOST` environment variable is automatically set

## Maintenance

### Updating OpenSearch Version

1. Update `opensearch_ec2_version` in `terraform.tfvars`
2. Apply Terraform changes
3. The user data script will pull the new image and restart the container

### Restarting OpenSearch

```bash
# Via SSM Session
aws ssm start-session --target <instance-id>
sudo docker restart opensearch
```

### Viewing OpenSearch Logs

```bash
# Via SSM Session
aws ssm start-session --target <instance-id>
sudo docker logs -f opensearch
```

## Cost Considerations

- **EC2 t3.micro**: Free tier eligible (750 hours/month for 12 months)
- **EBS storage**: ~$0.10/GB/month (20GB default = ~$2/month)
- **Data transfer**: Free within same VPC
- **Total**: ~$2/month after free tier expires

## Security Notes

- OpenSearch security plugins are **disabled** by default for simplicity
- OpenSearch is only accessible from within the VPC
- Consider enabling security plugins for production:
  ```bash
  # In user data script, remove:
  -e "plugins.security.disabled=true"
  ```

## Next Steps

1. Deploy the infrastructure:
   ```bash
   cd envs/dev
   terraform init
   terraform plan
   terraform apply
   ```

2. Verify OpenSearch is running:
   ```bash
   terraform output opensearch_ec2_endpoint
   ```

3. Test connection from ECS:
   - Check ECS task logs for OpenSearch connection
   - Verify `OPENSEARCH_HOST` environment variable is set

4. Monitor and adjust:
   - Monitor EC2 instance metrics
   - Adjust instance type or heap size if needed



