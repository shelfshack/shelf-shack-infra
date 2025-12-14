# Senior AWS Architect Analysis: OpenSearch Connection Issue

## Problem Statement
FastAPI service cannot connect to OpenSearch on EC2, receiving "Connection refused (Errno 111)" errors.

## Root Cause Analysis

### 1. Network Layer ✅ WORKING
- **Connection Type**: Connection refused (not timeout)
- **Implication**: Network path exists, security groups allow traffic
- **Evidence**: 
  - Security group rule exists: Port 9200 from ECS SG (sg-0dc4c85d094cf5a2e) → OpenSearch SG (sg-0f0cde98208642210)
  - IP configuration correct: 10.0.10.181 matches Terraform output
  - ECS service has correct OPENSEARCH_HOST env var

### 2. Application Layer ❌ FAILING
- **Symptom**: No service listening on port 9200
- **Root Cause**: OpenSearch container not running or not bound to 0.0.0.0
- **Evidence**:
  - Instance created: 2025-12-14T04:19:43 (very recent)
  - Connection refused = TCP handshake fails (no listener)
  - User data script execution status unknown

### 3. Configuration Analysis

**User Data Script Logic**:
- Conditional based on `opensearch_security_disabled` (default: false = security enabled)
- When security enabled: Requires `OPENSEARCH_INITIAL_ADMIN_PASSWORD`
- Password set to: `OpenSearch@2024!` (meets requirements)

**Potential Issues**:
1. User data script may have failed during execution
2. Container may have failed to start (password validation, resource constraints)
3. Container may be binding to localhost instead of 0.0.0.0
4. OpenSearch may require additional time to initialize

## Solution Architecture

### Immediate Fix (Recommended)
**Recreate instance with verified configuration**:
```bash
cd envs/dev
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

**Why this works**:
- Ensures user data script runs with latest configuration
- Password is correctly set: `OpenSearch@2024!`
- `network.host=0.0.0.0` ensures binding to all interfaces
- Improved error handling and logging in user data

### Verification Steps
1. Wait 3-4 minutes after instance creation
2. Check CloudWatch logs (if enabled) for user data execution
3. Test from ECS task: `curl http://10.0.10.181:9200/_cluster/health`
4. Monitor ECS service logs for successful connections

### Long-term Improvements

1. **Health Checks & Monitoring**:
   - Add CloudWatch alarm for container status
   - Implement health check endpoint
   - Monitor OpenSearch cluster health

2. **Auto-Recovery**:
   - Use Systems Manager Automation for auto-recovery
   - Implement container health checks with auto-restart

3. **Resource Optimization**:
   - Monitor memory usage (t3.micro may be insufficient)
   - Consider t3.small if OOM errors occur
   - Adjust Java heap size based on instance type

4. **Accessibility**:
   - Ensure SSM endpoints are working for remote access
   - Consider moving to public subnet temporarily for debugging
   - Or use bastion host for access

## Expected Timeline
- Instance creation: ~2 minutes
- User data execution: ~3-5 minutes
- OpenSearch initialization: ~1-2 minutes
- **Total**: 5-8 minutes for full readiness

## Success Criteria
- Container running: `docker ps | grep opensearch`
- Port listening: `netstat -tlnp | grep 9200`
- Health check passes: `curl http://10.0.10.181:9200/_cluster/health`
- ECS service connects successfully
