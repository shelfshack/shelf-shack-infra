# All Changes Made to Fix OpenSearch

## Critical Fixes Applied

### 1. Fixed Docker Installation (modules/opensearch_ec2/main.tf)
**Problem**: Script tried to install `curl` which conflicts with `curl-minimal` pre-installed in Amazon Linux 2023. Script exited immediately with `set -e`.

**Fix**: Removed `curl` from installation line
```bash
# BEFORE (line ~81):
sudo yum install -y docker curl

# AFTER:
sudo yum install -y docker
```

### 2. Fixed OpenSearch Container Startup (modules/opensearch_ec2/main.tf)
**Problem**: OpenSearch 3.x requires `OPENSEARCH_INITIAL_ADMIN_PASSWORD` even when security is disabled. Container was failing to start.

**Fix**: Added password environment variable even when security is disabled (lines 139-157)
```bash
# When security_disabled = true, now includes:
-e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=${var.opensearch_admin_password}"
-e "DISABLE_SECURITY_PLUGIN=true"
-e "DISABLE_INSTALL_DEMO_CONFIG=true"
```

### 3. Enhanced Error Handling
**Added**:
- Better Docker readiness checks (waits up to 10 attempts)
- Container status verification
- Port listening verification
- Health check with external IP testing

### 4. Fixed terraform.tfvars
**Added**:
- `opensearch_ec2_security_disabled = true`
- `enable_opensearch_ec2 = true`

### 5. Added Missing Output (envs/dev/outputs.tf)
**Added**:
- `service_security_group_id` output for diagnostic scripts

## Why Terraform Apply Might Not Have Worked

If you ran `terraform apply` multiple times and it's still not working, possible reasons:

1. **Instance wasn't recreated** - Terraform only recreates if the resource changes
2. **User_data changes don't trigger recreation** - Changing user_data alone doesn't recreate the instance
3. **Container failed after user_data** - Container might have started then crashed

## Solution: Force Recreation

You MUST taint the instance to force recreation:

```bash
cd envs/dev

# This forces Terraform to destroy and recreate
terraform taint module.opensearch_ec2[0].aws_instance.opensearch

# Now apply will recreate with new user_data
terraform apply -var-file=terraform.tfvars
```

## Verification

After recreation, check:
1. User data log: `/var/log/user-data.log` on instance
2. Container status: `docker ps | grep opensearch`
3. Port listening: `netstat -tlnp | grep 9200`
4. Health check: `curl http://<ip>:9200/_cluster/health`

## Current File Locations

- User data script: `modules/opensearch_ec2/main.tf` (lines 73-245)
- Configuration: `envs/dev/terraform.tfvars` (lines 101-103)
- Outputs: `envs/dev/outputs.tf` (lines 11-16)
