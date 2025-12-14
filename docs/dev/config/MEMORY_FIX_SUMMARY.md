# Memory Fix Summary

## Problem
- t3.micro has **1GB total RAM** (~916MB available after OS)
- OpenSearch 2.11.0 with **256m heap** was too heavy
- Container was being **OOM killed** (Out of Memory)
- System became unresponsive, SSM sessions hung

## Fixes Applied

### 1. Reduced Heap Size ✅
- Changed from `256m` → `128m` in `terraform.tfvars`
- File: `envs/dev/terraform.tfvars` line 107

### 2. Added Docker Memory Limits ✅
- Added `--memory="512m"` to container
- Added `--memory-swap="512m"` (no swap, hard limit)
- Prevents container from consuming all system memory
- File: `modules/opensearch_ec2/main.tf` lines 125-126, 147-148

### 3. Added OOM Detection ✅
- Script now checks for OOM kills
- Shows exit code and OOM status
- Displays system memory usage
- File: `modules/opensearch_ec2/main.tf` lines 177-200

## Next Steps

### Option 1: Recreate Instance (Recommended)
The current instance is likely unresponsive. Recreate it:

```bash
cd envs/dev

# Taint to force recreation
terraform taint module.opensearch_ec2[0].aws_instance.opensearch

# Apply with new memory settings
terraform apply -var-file=terraform.tfvars
```

**Expected result:**
- Container starts with 128m heap
- Docker memory limit: 512m
- System has ~400MB free for OS
- No OOM kills

### Option 2: Use Larger Instance (If 128m Still Fails)
If t3.micro is still too small, upgrade to **t3.small** (2GB RAM):

```bash
# In terraform.tfvars, find opensearch_ec2_instance_type
# Change from t3.micro to t3.small
```

Then:
```bash
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

## Memory Breakdown (t3.micro with fixes)

- **Total RAM**: 1GB (916MB available)
- **OS + Docker**: ~400MB
- **Container limit**: 512MB
- **OpenSearch heap**: 128MB
- **Remaining**: ~400MB for OS

This should work, but t3.small (2GB) is more comfortable.

## Verification

After recreation, check:
```bash
# Via SSM Session Manager
sudo docker ps
sudo docker stats opensearch --no-stream
free -h
sudo docker logs opensearch --tail 30
curl http://localhost:9200/_cluster/health
```

Expected:
- Container status: "Up X minutes" (not restarting)
- Memory usage: ~200-300MB (well under 512MB limit)
- Health check: Returns JSON with "status": "green" or "yellow"
