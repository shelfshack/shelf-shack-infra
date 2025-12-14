# Fix: Duplicate Setting Error

## Problem
Container is restarting with exit code 64 due to:
```
ERROR: setting [plugins.security.disabled] already set, saw [true] and [true]
```

## Root Cause
We're setting `plugins.security.disabled=true` twice:
1. Via environment variable: `-e "plugins.security.disabled=true"`
2. Via `DISABLE_SECURITY_PLUGIN=true` (which also sets it)

OpenSearch 2.11.0 doesn't allow duplicate settings.

## Fix Applied
Removed `DISABLE_SECURITY_PLUGIN=true` - we only need `plugins.security.disabled=true`.

## Next Steps

### Option 1: Fix Current Container (Quick)
If you have Session Manager access:

```bash
# Stop and remove current container
sudo docker stop opensearch
sudo docker rm opensearch

# Start with fixed configuration (no DISABLE_SECURITY_PLUGIN)
sudo docker run -d \
  --name opensearch \
  --restart unless-stopped \
  -p 9200:9200 \
  -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "network.host=0.0.0.0" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx256m" \
  -e "plugins.security.disabled=true" \
  -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=OpenSearch@2024!" \
  -e "DISABLE_INSTALL_DEMO_CONFIG=true" \
  -v opensearch-data:/usr/share/opensearch/data \
  opensearchproject/opensearch:2.11.0

# Wait and check
sleep 30
sudo docker ps
sudo docker logs opensearch --tail 30
curl http://localhost:9200/_cluster/health
```

### Option 2: Recreate Instance (Recommended)
```bash
cd envs/dev
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

The fixed user_data script will now use the correct configuration without duplicate settings.
