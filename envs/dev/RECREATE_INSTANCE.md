# Recreate OpenSearch EC2 Instance - Recommended Fix

## Why Recreate?
The container is not running and SSM commands are unreliable. Recreating the instance ensures:
1. The fixed user_data script runs automatically
2. Docker is installed correctly
3. OpenSearch container starts with proper configuration
4. All fixes are applied from scratch

## Steps

### 1. Taint the instance
```bash
cd envs/dev
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
```

### 2. Apply Terraform
```bash
terraform apply -var-file=terraform.tfvars
```

This will:
- Destroy the old instance
- Create a new instance with the fixed user_data script
- The user_data script will:
  - Install Docker (without curl conflict)
  - Start OpenSearch container with correct settings
  - Include password even when security is disabled (for OpenSearch 3.x)

### 3. Wait for Initialization
Wait **5-8 minutes** for:
- Instance creation: ~2 minutes
- User data execution: ~2-3 minutes
- OpenSearch initialization: ~1-2 minutes

### 4. Verify
```bash
# Check container status
./diagnose_opensearch_complete.sh

# Test connection
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host)
curl http://${OPENSEARCH_IP}:9200/_cluster/health
```

### 5. Restart ECS Service
After OpenSearch is running, restart ECS to pick up the connection:
```bash
aws ecs update-service \
  --cluster rentify-dev-cluster \
  --service rentify-dev-service \
  --force-new-deployment
```

### 6. Monitor Logs
```bash
aws logs tail /ecs/rentify-dev --follow
```

You should see successful OpenSearch connections instead of "Connection refused" errors.

## Expected Result
- Container running: `docker ps | grep opensearch` shows "Up X minutes"
- Port listening: `netstat -tlnp | grep 9200` shows port 9200
- Health check: `curl http://10.0.10.XXX:9200/_cluster/health` returns JSON
- ECS connects: No more connection errors in logs
- API uses OpenSearch: Categories endpoint uses OpenSearch instead of PostgreSQL fallback
