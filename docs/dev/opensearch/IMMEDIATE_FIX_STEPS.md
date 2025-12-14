# Immediate Fix Steps

## Current Situation
- Instance recreated but container still not running
- SSM commands return empty (connectivity issues)
- Connection refused errors persist

## Option 1: Check EC2 Console (Recommended First Step)

1. **Go to AWS Console → EC2 → Instances**
2. **Find instance**: i-0128eeadc627beac0
3. **Check system log**:
   - Select instance
   - Actions → Monitor and troubleshoot → Get system log
   - Look for user_data execution output
   - Check for errors

4. **Try Session Manager**:
   - Select instance
   - Click "Connect" → "Session Manager"
   - If available, run:
     ```bash
     sudo tail -100 /var/log/user-data.log
     sudo docker ps -a
     sudo docker logs opensearch --tail 50 2>&1 || echo "No container"
     ```

## Option 2: Recreate with Specific Version (Just Added)

I've updated `terraform.tfvars` to use OpenSearch 2.11.0 instead of latest:

```bash
cd envs/dev

# Recreate with stable version
terraform taint module.opensearch_ec2[0].aws_instance.opensearch
terraform apply -var-file=terraform.tfvars
```

This uses:
- **Version 2.11.0** (stable, not latest)
- **256m heap** (fits better in t3.micro)
- **All previous fixes** still apply

## Option 3: Manual Fix via Session Manager

If you can access the instance:

```bash
# Check what's wrong
sudo docker ps -a
sudo tail -100 /var/log/user-data.log

# If Docker is installed but container not running:
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

# Verify
sudo docker ps
sudo docker logs opensearch --tail 30
curl http://localhost:9200/_cluster/health
```

## Next Steps

1. **First**: Check EC2 Console system log to see what failed
2. **Then**: Either recreate with version 2.11.0 OR manually fix via Session Manager
3. **Finally**: Restart ECS service after container is running
