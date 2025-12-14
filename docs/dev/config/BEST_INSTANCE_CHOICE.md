# ✅ Best Instance Choice: m7i-flex.large

## Comparison of Free Tier Options

| Instance Type | RAM | vCPU | Best For |
|--------------|-----|------|----------|
| **m7i-flex.large** | **8GB** | 2 | **✅ BEST - OpenSearch** |
| c7i-flex.large | 4GB | 2 | Good, but less RAM |
| t3.small | 2GB | 2 | Minimal, works but tight |
| t4g.small | 2GB | 2 | ARM-based, less compatible |
| t3.micro | 1GB | 2 | ❌ Too small (OOM issues) |

## Why m7i-flex.large is BEST

1. **8GB RAM** - 4x more than t3.small!
2. **2 vCPU** - Good for indexing/searching
3. **x86_64 architecture** - Best Docker image compatibility
4. **FREE TIER eligible** - No cost!
5. **Plenty of headroom** - No memory pressure

## Configuration Updated

✅ **Instance Type**: `m7i-flex.large` (8GB RAM)
✅ **Java Heap**: `2g` (optimal for 8GB system)
✅ **Docker Memory Limit**: `4g` (allows heap + overhead)

## Memory Breakdown (m7i-flex.large)

- **Total RAM**: 8GB (~7.5GB available)
- **OS + Docker**: ~500MB
- **Container limit**: 4GB
- **OpenSearch heap**: 2GB
- **Remaining**: ~5GB for OS (plenty!)

## Next Steps

```bash
cd envs/dev

# Taint to force recreation with m7i-flex.large
terraform taint module.opensearch_ec2[0].aws_instance.opensearch

# Apply with best instance type
terraform apply -var-file=terraform.tfvars
```

## Why This Will Work Perfectly

- **8GB RAM** is excellent for OpenSearch
- **2GB heap** is optimal for production-like performance
- **No OOM kills** - massive headroom
- **Fast indexing** - more memory = better performance
- **Still FREE** - within Free Tier!

## Expected Performance

- ✅ Fast startup (no memory pressure)
- ✅ Smooth indexing operations
- ✅ No connection refused errors
- ✅ Stable, production-ready setup
- ✅ Can handle larger datasets

## Verification

After recreation (wait 5-8 minutes):

```bash
# Check instance type
aws ec2 describe-instances \
  --instance-ids $(terraform output -raw opensearch_ec2_instance_id) \
  --query 'Reservations[0].Instances[0].InstanceType' \
  --output text

# Should show: m7i-flex.large

# Check via SSM
sudo docker ps
sudo docker stats opensearch --no-stream
free -h
curl http://localhost:9200/_cluster/health
```

Expected:
- Instance type: `m7i-flex.large`
- Container: "Up X minutes" (stable)
- Memory: ~2-3GB usage (well under 8GB)
- Health: Returns JSON with "status": "green"
- **No more connection refused errors!**
