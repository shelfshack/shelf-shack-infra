# Final Fix: OpenSearch Connection Refused

## Current Status
- ✅ Security groups: Correctly configured
- ✅ ECS environment variables: Set correctly
- ✅ Network configuration: Correct
- ❌ **Container: Not running or not accessible**

## Root Cause
The OpenSearch container is either:
1. Not running on the EC2 instance
2. Not listening on port 9200
3. Failed to start due to configuration issues

## Immediate Fix

Run the comprehensive fix script:

```bash
cd envs/dev
./ensure_opensearch_running.sh
```

This script will:
1. Check if Docker is installed
2. Stop and remove any existing container
3. Start a new container with correct configuration
4. Verify it's running and listening on port 9200
5. Test the health endpoint

## Alternative: Recreate Instance

If SSM commands are not working, recreate the instance:

```bash
cd envs/dev
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

Wait 5-8 minutes for full initialization.

## After Fix

1. **Verify container is running:**
   ```bash
   ./diagnose_opensearch_complete.sh
   ```

2. **Test connection from ECS:**
   - Check ECS logs: `aws logs tail /ecs/shelfshack-dev --follow`
   - Should see successful OpenSearch connections

3. **Restart ECS service if needed:**
   ```bash
   aws ecs update-service \
     --cluster shelfshack-dev-cluster \
     --service shelfshack-dev-service \
     --force-new-deployment
   ```

## Expected Result

After the fix:
- Container status: "Up X minutes" (not "Restarting")
- Port 9200 listening
- Health check: `{"status":"green"}` or `{"status":"yellow"}`
- No more "Connection refused" errors in ECS logs
- API endpoint returns data successfully
