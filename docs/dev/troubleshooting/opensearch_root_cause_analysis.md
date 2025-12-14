# OpenSearch Connection Issue - Root Cause Analysis

## Executive Summary
**Status**: Connection Refused (Errno 111)  
**Root Cause**: OpenSearch container is not running on EC2 instance  
**Impact**: FastAPI service cannot connect to OpenSearch, falling back to PostgreSQL

## Infrastructure Analysis

### ✅ What's Working
1. **Network Connectivity**: Connection refused (not timeout) = network path exists
2. **Security Groups**: Correctly configured
   - ECS Service SG: `sg-0dc4c85d094cf5a2e`
   - OpenSearch EC2 SG: `sg-0f0cde98208642210`
   - Rule exists: Port 9200 from ECS SG → OpenSearch SG
3. **Instance Status**: Running and healthy
4. **IP Configuration**: Correct (10.0.10.181 matches Terraform output)
5. **ECS Configuration**: OPENSEARCH_HOST env var is set correctly

### ❌ What's Not Working
1. **OpenSearch Container**: Not running or not listening on port 9200
2. **SSM Access**: Connection lost - cannot access instance remotely
3. **User Data Execution**: Unknown if script completed successfully

## Root Cause Analysis

### Primary Issue: Container Not Running

**Evidence**:
- Connection refused = TCP connection reaches the host but no service on port 9200
- Instance was recently created (2025-12-14T04:19:43)
- Security groups allow traffic (no firewall blocking)

**Possible Causes**:
1. **User Data Script Failed**: 
   - Docker installation failed
   - OpenSearch container failed to start (password validation, resource constraints)
   - Script execution error

2. **Container Startup Failure**:
   - Password validation failed (we fixed this, but instance may have been created before fix)
   - Insufficient memory (t3.micro may be too small)
   - Docker daemon not running

3. **Container Crashed After Start**:
   - Out of memory
   - Configuration error
   - Port conflict

## Solution Strategy

### Immediate Fix (Recommended)
**Recreate instance with fixed user data script**:
- User data now includes correct password: `OpenSearch@2024!`
- Improved error handling and logging
- Better health checks

### Long-term Improvements
1. **Monitoring**: Add CloudWatch alarms for container status
2. **Health Checks**: Implement health check endpoint
3. **Auto-recovery**: Use Systems Manager Automation for auto-recovery
4. **Resource Sizing**: Consider t3.small if t3.micro is insufficient

