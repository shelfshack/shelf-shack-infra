# Final Fix Summary - OpenSearch Connection Issue

## Root Cause Identified ✅
The user_data script failed because Amazon Linux 2023 has `curl-minimal` pre-installed, and trying to install `curl` causes a package conflict. The script uses `set -e`, so it exited immediately, preventing Docker from being installed.

## Fixes Applied ✅

### 1. Fixed user_data Script
- **File**: `modules/opensearch_ec2/main.tf`
- **Change**: Removed `curl` from installation (Amazon Linux 2023 already has `curl-minimal`)
- **Result**: Script will now complete successfully

### 2. Fixed Diagnostic Script
- **File**: `envs/dev/diagnose_opensearch_complete.sh`
- **Change**: Fixed ECS security group detection to use Terraform output
- **Result**: Diagnostic script will correctly identify security group rules

### 3. Created Quick Fix Script
- **File**: `envs/dev/fix_docker_and_opensearch.sh`
- **Purpose**: Manually install Docker and start OpenSearch on current instance
- **Usage**: `./fix_docker_and_opensearch.sh`

## Recommended Action

### Option 1: Recreate Instance (Best Practice)
This ensures clean state with all fixes:
```bash
cd envs/dev
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```
Wait 5-8 minutes for full initialization.

### Option 2: Quick Fix Current Instance
If you want to fix without recreating:
```bash
cd envs/dev
./fix_docker_and_opensearch.sh
```
Wait 1-2 minutes, then verify with:
```bash
./diagnose_opensearch_complete.sh
```

## Verification Checklist

After applying the fix, verify:
- [ ] Docker is installed: `docker --version` (via SSM)
- [ ] OpenSearch container is running: `docker ps | grep opensearch`
- [ ] Port 9200 is listening: `netstat -tlnp | grep 9200`
- [ ] Health check passes: `curl http://10.0.10.211:9200/_cluster/health`
- [ ] ECS service can connect (check ECS logs)

## Expected Timeline

- **Instance recreation**: 5-8 minutes
- **Quick fix script**: 1-2 minutes
- **OpenSearch initialization**: 1-2 minutes after container starts

## Next Steps After Fix

1. Monitor ECS logs for successful connections:
   ```bash
   aws logs tail /ecs/rentify-dev --follow
   ```

2. If still seeing errors, restart ECS service:
   ```bash
   aws ecs update-service \
     --cluster rentify-dev-cluster \
     --service rentify-dev-service \
     --force-new-deployment
   ```

3. Verify no more "Connection refused" errors in logs
