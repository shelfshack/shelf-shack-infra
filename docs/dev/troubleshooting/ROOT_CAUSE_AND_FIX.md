# Root Cause Analysis: Why Container Still Not Running

## Problem
Even after recreating the instance, the OpenSearch container is still not running. SSM commands return empty, indicating connectivity issues.

## Possible Root Causes

### 1. User Data Script Failed Silently
- Docker installation might have failed
- Container might have started then crashed
- Script might have exited before container started

### 2. OpenSearch Version Issue
- Using `latest` tag might pull OpenSearch 3.x which has different requirements
- Container might be failing due to resource constraints (t3.micro might be too small)

### 3. SSM Agent Not Ready
- Instance might not have internet access or VPC endpoints
- SSM agent might not be installed/configured properly

## Solution: Use Specific OpenSearch Version

Instead of `latest`, use a stable version that works better with t3.micro:

```bash
# Add to terraform.tfvars:
opensearch_ec2_image   = "opensearchproject/opensearch"
opensearch_ec2_version = "2.11.0"  # Stable version, not latest
opensearch_ec2_java_heap_size = "256m"  # Smaller heap for t3.micro
```

## Alternative: Check via EC2 Console

1. Go to EC2 Console → Instances
2. Find instance: i-0128eeadc627beac0
3. Click "Connect" → "Session Manager" (if available)
4. Or check "Get system log" to see user_data output

## Manual Fix via EC2 Console

If you can access the instance via Session Manager:

```bash
# Check Docker
sudo docker ps -a

# Check user_data log
sudo tail -100 /var/log/user-data.log

# If container not running, start it manually:
sudo docker run -d \
  --name opensearch \
  --restart unless-stopped \
  -p 9200:9200 \
  -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "network.host=0.0.0.0" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx256m" \
  -e "plugins.security.disabled=true" \
  -e "DISABLE_SECURITY_PLUGIN=true" \
  -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=OpenSearch@2024!" \
  -e "DISABLE_INSTALL_DEMO_CONFIG=true" \
  -v opensearch-data:/usr/share/opensearch/data \
  opensearchproject/opensearch:2.11.0

# Check if it's running
sudo docker ps
sudo docker logs opensearch --tail 30
```

## Next Steps

1. **Check EC2 Console** for user_data logs
2. **Add version to tfvars** to use stable 2.11.0 instead of latest
3. **Recreate instance** with specific version
4. **Or manually fix** via Session Manager if available
