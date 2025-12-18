# Final Solution: Recreate OpenSearch Instance

## Current Status
- ❌ OpenSearch container is NOT running on EC2 instance
- ❌ ECS cannot connect: "Connection refused" errors
- ❌ SSM commands are unreliable
- ❌ ECS Exec is not enabled/working

## Root Cause
The container failed to start, likely because:
1. Docker installation failed (curl conflict issue - now fixed)
2. Container failed to start (password requirement for OpenSearch 3.x - now fixed)
3. User_data script didn't complete successfully

## Solution: Recreate Instance

The user_data script has been fixed. Recreating the instance will ensure it runs correctly:

```bash
cd envs/dev

# Step 1: Taint the instance to force recreation
terraform taint module.opensearch_ec2[0].aws_instance.opensearch

# Step 2: Apply to recreate with fixed user_data
terraform apply -var-file=terraform.tfvars
```

## What the Fixed user_data Script Does

1. ✅ Installs Docker (without curl conflict)
2. ✅ Waits for Docker to be ready
3. ✅ Removes any existing container
4. ✅ Starts OpenSearch with:
   - Security disabled (as configured)
   - Password provided (required for OpenSearch 3.x even when security is disabled)
   - Network binding to 0.0.0.0 (all interfaces)
   - Proper environment variables

## After Recreation

### 1. Wait 5-8 minutes
- Instance creation: ~2 min
- User data execution: ~2-3 min
- OpenSearch initialization: ~1-2 min

### 2. Verify Container is Running
```bash
# Check status
./diagnose_opensearch_complete.sh

# Should show:
# - Container running
# - Port 9200 listening
# - Health check passing
```

### 3. Restart ECS Service
```bash
aws ecs update-service \
  --cluster shelfshack-dev-cluster \
  --service shelfshack-dev-service \
  --force-new-deployment
```

### 4. Monitor Logs
```bash
aws logs tail /ecs/shelfshack-dev --follow
```

You should see:
- ✅ Successful OpenSearch connections
- ✅ No more "Connection refused" errors
- ✅ API using OpenSearch instead of PostgreSQL fallback

## Expected Result

After recreation and ECS restart:
- Container: Running and healthy
- Port 9200: Listening
- ECS: Can connect successfully
- API: Uses OpenSearch for search operations
- Logs: No connection errors

## Why This Works

Recreating the instance ensures:
1. Clean state - no leftover failed containers
2. Latest user_data script runs automatically
3. All fixes are applied from scratch
4. No manual intervention needed

This is the most reliable solution given that SSM and ECS Exec are not working.
