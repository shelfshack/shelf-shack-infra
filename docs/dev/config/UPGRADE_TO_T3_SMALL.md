# ✅ Upgrade to t3.small (FREE TIER!)

## Great News!

Your AWS account has **t3.small available in Free Tier**! 

This means you can use a **2GB RAM instance** instead of 1GB, which will solve all memory issues.

## Changes Made

1. ✅ **Instance Type**: `t3.micro` → `t3.small` (2GB RAM)
2. ✅ **Heap Size**: `128m` → `512m` (more comfortable)
3. ✅ **Docker Memory Limit**: Still `512m` (but now plenty of headroom)

## Memory Breakdown (t3.small)

- **Total RAM**: 2GB (~1.8GB available)
- **OS + Docker**: ~400MB
- **Container limit**: 512MB
- **OpenSearch heap**: 512MB
- **Remaining**: ~900MB for OS (plenty of headroom!)

## Next Steps

```bash
cd envs/dev

# Taint to force recreation with t3.small
terraform taint module.opensearch_ec2[0].aws_instance.opensearch

# Apply with new instance type
terraform apply -var-file=terraform.tfvars
```

## Why This Will Work

- **2GB RAM** is plenty for OpenSearch + OS
- **512m heap** is a comfortable size for OpenSearch
- **No OOM kills** - plenty of memory headroom
- **Still FREE** - t3.small is in your Free Tier!

## Verification

After recreation (wait 5-8 minutes):

```bash
# Check instance type
aws ec2 describe-instances \
  --instance-ids $(terraform output -raw opensearch_ec2_instance_id) \
  --query 'Reservations[0].Instances[0].InstanceType' \
  --output text

# Should show: t3.small

# Check via SSM
sudo docker ps
sudo docker stats opensearch --no-stream
free -h
curl http://localhost:9200/_cluster/health
```

Expected:
- Instance type: `t3.small`
- Container: "Up X minutes" (stable)
- Memory: ~400-500MB usage (well under 2GB)
- Health: Returns JSON with "status": "green"
