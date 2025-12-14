# OpenSearch Container Restarting - Fix Summary

## Root Cause Identified ✅

The container is stuck in a restart loop because:
1. **OpenSearch 3.3.2 (latest)** is being used
2. **OpenSearch 2.12.0+ requires a password** even when security is "disabled"
3. The container fails to start without `OPENSEARCH_INITIAL_ADMIN_PASSWORD` set
4. Container keeps restarting: "Restarting (1) 41 seconds ago"

## Fix Applied ✅

Updated `modules/opensearch_ec2/main.tf` user_data script to:
- Add `OPENSEARCH_INITIAL_ADMIN_PASSWORD` even when security is disabled
- Add `DISABLE_SECURITY_PLUGIN=true` for extra assurance
- Add `DISABLE_INSTALL_DEMO_CONFIG=true` to prevent demo config installation

This ensures OpenSearch 3.x versions can start properly even with security disabled.

## Immediate Fix Options

### Option 1: Fix Current Container (Quick)
Run the fix script to restart the container with correct settings:
```bash
cd envs/dev
./fix_opensearch_container.sh
```

### Option 2: Recreate Instance (Recommended)
This ensures the fixed user_data script runs:
```bash
cd envs/dev
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

## Verification

After fixing, verify:
1. Container is running (not restarting): `docker ps | grep opensearch`
2. Port 9200 is listening: `netstat -tlnp | grep 9200`
3. Health check passes: `curl http://localhost:9200/_cluster/health`
4. ECS can connect (check ECS logs)

## Expected Result

- Container status: "Up X minutes" (not "Restarting")
- Port 9200 listening
- Health check returns: `{"status":"green"}` or `{"status":"yellow"}`
- No more "Connection refused" errors in ECS logs
