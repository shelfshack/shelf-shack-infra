# OpenSearch Connection Fix - Complete Analysis

## Issues Found

1. **Security Configuration Mismatch**
   - `opensearch_ec2_security_disabled` was not set in `terraform.tfvars`
   - Default is `false` (security enabled), but container may not be starting properly
   - **FIX**: Added `opensearch_ec2_security_disabled = true` to `terraform.tfvars`

2. **User Data Script Improvements**
   - Enhanced error handling and logging
   - Better Docker readiness checks
   - Improved container status verification
   - Added port listening verification
   - Enhanced health check logic

3. **ECS Environment Variables**
   - Currently set with username/password (admin/OpenSearch@2024!)
   - If security is disabled, these should not be needed
   - FastAPI should handle both cases (with/without auth)

## Configuration Status

### Terraform Configuration
- ✅ Security groups: Correctly configured (port 9200 from ECS SG)
- ✅ IP configuration: Correct (10.0.10.229)
- ✅ ECS environment variables: Set (OPENSEARCH_HOST, PORT, USERNAME, PASSWORD)
- ⚠️  Security disabled: Now set to `true` in terraform.tfvars

### Network Configuration
- ✅ Security group rules exist for port 9200
- ✅ ECS can reach OpenSearch EC2 instance
- ✅ IP addresses match

### Container Status
- ⚠️  Container may not be running (SSM commands return empty)
- ⚠️  Port 9200 may not be listening

## Recommended Actions

### Step 1: Recreate Instance with New Configuration
```bash
cd envs/dev
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

### Step 2: Wait for Initialization
Wait 5-8 minutes for:
- Instance creation (2 min)
- User data execution (2-3 min)  
- OpenSearch initialization (1-2 min)

### Step 3: Run Diagnostic Script
```bash
./diagnose_opensearch_complete.sh
```

### Step 4: If Security is Disabled, Update ECS Environment
Since security is now disabled, you may want to remove OPENSEARCH_USERNAME and OPENSEARCH_PASSWORD from ECS environment variables. However, FastAPI should handle both cases.

### Step 5: Restart ECS Service
```bash
aws ecs update-service \
  --cluster rentify-dev-cluster \
  --service rentify-dev-service \
  --force-new-deployment
```

### Step 6: Monitor Logs
```bash
aws logs tail /ecs/rentify-dev --follow
```

## FastAPI Configuration Check

FastAPI should:
1. Check if `OPENSEARCH_USERNAME` and `OPENSEARCH_PASSWORD` are set
2. If set, use basic auth
3. If not set, connect without auth
4. Handle connection errors gracefully (fallback to PostgreSQL)

## Expected Behavior After Fix

1. Container starts successfully with security disabled
2. Port 9200 listens on 0.0.0.0 (all interfaces)
3. FastAPI connects without authentication
4. No more "Connection refused" errors

## Troubleshooting

If issues persist:
1. Check user data logs: `/var/log/user-data.log` on EC2 instance
2. Check container logs: `docker logs opensearch`
3. Verify port listening: `netstat -tlnp | grep 9200`
4. Test from ECS task: `curl http://10.0.10.229:9200/_cluster/health`
