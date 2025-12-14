# Final Analysis: Container Crashed Immediately

## What the System Log Shows

1. ✅ Docker installed successfully
2. ✅ Container started (ID: d1a1e5148398fa7ab0b596240d3bf16f5bc2096a2eb48e3e6662559d30ecdc33)
3. ❌ Script hangs at "Verifying container started..."
4. ❌ Using `latest` tag (OpenSearch 3.x) instead of 2.11.0

## Root Cause

The container **crashed immediately** after starting because:
- **OpenSearch 3.x (`latest`)** requires more resources than t3.micro (1GB RAM) can provide
- Container likely hit OOM (Out of Memory) and was killed
- The script hangs because `docker ps` check is waiting indefinitely

## Why Version 2.11.0 Wasn't Used

The instance was created **before** we added the version to `terraform.tfvars`, so it used the default `latest`.

## Solution

### 1. Fixed the Hanging Script
- Added timeout to container check (6 attempts, 5 seconds each)
- Shows container logs if it crashed
- Shows exit code to diagnose the issue
- Doesn't exit - continues to show diagnostic info

### 2. Recreate with Version 2.11.0

```bash
cd envs/dev

# Force recreation with new version
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

This will:
- Use OpenSearch 2.11.0 (stable, lighter)
- Use 256m heap (fits in t3.micro)
- Include all fixes (password, network binding)
- Not hang if container crashes (will show logs)

### 3. After Recreation

Wait 5-8 minutes, then check:
```bash
./diagnose_opensearch_complete.sh
```

The script will now show container logs if it crashed, helping diagnose the issue.

## Expected Result

With version 2.11.0 and 256m heap:
- Container should start successfully
- Port 9200 should be listening
- Health check should pass
- ECS should be able to connect
