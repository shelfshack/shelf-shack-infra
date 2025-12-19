#!/bin/bash
# Quick fix script to install Docker and start OpenSearch container on existing instance

set -e

SCRIPT_DIR="$(SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/envs/dev" cd "$(dirname "$0")"cd "$(dirname "$0")" pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/envs/dev"cd "$(dirname "$0")" pwd)"
cd "$REPO_ROOT/envs/dev"

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null || echo "")
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ]; then
  echo "ERROR: Could not get instance ID from Terraform"
  exit 1
fi

echo "=== FIXING OPENSEARCH EC2 INSTANCE ==="
echo "Instance ID: $INSTANCE_ID"
echo "OpenSearch IP: $OPENSEARCH_IP"
echo ""

# Check if security is disabled
if grep -q "opensearch_ec2_security_disabled.*=.*true" terraform.tfvars 2>/dev/null; then
  SECURITY_DISABLED=true
  echo "Security: DISABLED (no password)"
else
  SECURITY_DISABLED=false
  OPENSEARCH_PASSWORD=$(grep "opensearch_ec2_admin_password" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "OpenSearch@2024!")
  echo "Security: ENABLED (password: $OPENSEARCH_PASSWORD)"
fi

# Get OpenSearch version and image from tfvars or use defaults
OPENSEARCH_IMAGE=$(grep "opensearch_ec2_image" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "opensearchproject/opensearch")
OPENSEARCH_VERSION=$(grep "opensearch_ec2_version" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "2.11.0")
JAVA_HEAP_SIZE=$(grep "opensearch_ec2_java_heap_size" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "512m")

echo "OpenSearch Image: ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}"
echo "Java Heap: $JAVA_HEAP_SIZE"
echo ""

# Create a temporary script file for SSM
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" << 'SCRIPT_EOF'
#!/bin/bash
set -e

echo "=== Installing Docker ==="
sudo yum install -y docker || echo "Docker may already be installed"

echo "=== Starting Docker ==="
sudo systemctl start docker
sudo systemctl enable docker

echo "=== Waiting for Docker to be ready ==="
for i in {1..10}; do
  if sudo docker info > /dev/null 2>&1; then
    echo "Docker is ready"
    break
  fi
  echo "Waiting for Docker... ($i/10)"
  sleep 2
done

echo "=== Removing existing container if present ==="
if sudo docker ps -a --format '{{.Names}}' | grep -q '^opensearch$'; then
  sudo docker stop opensearch || true
  sudo docker rm opensearch || true
fi

echo "=== Starting OpenSearch container ==="
SCRIPT_EOF

# Add the appropriate Docker run command based on security setting
if [ "$SECURITY_DISABLED" = "true" ]; then
  cat >> "$TEMP_SCRIPT" << SCRIPT_EOF
sudo docker run -d \\
  --name opensearch \\
  --restart unless-stopped \\
  -p 9200:9200 \\
  -p 9600:9600 \\
  -e "discovery.type=single-node" \\
  -e "network.host=0.0.0.0" \\
  -e "OPENSEARCH_JAVA_OPTS=-Xms${JAVA_HEAP_SIZE} -Xmx${JAVA_HEAP_SIZE}" \\
  -e "plugins.security.disabled=true" \\
  -v opensearch-data:/usr/share/opensearch/data \\
  ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}
SCRIPT_EOF
else
  cat >> "$TEMP_SCRIPT" << SCRIPT_EOF
sudo docker run -d \\
  --name opensearch \\
  --restart unless-stopped \\
  -p 9200:9200 \\
  -p 9600:9600 \\
  -e "discovery.type=single-node" \\
  -e "network.host=0.0.0.0" \\
  -e "OPENSEARCH_JAVA_OPTS=-Xms${JAVA_HEAP_SIZE} -Xmx${JAVA_HEAP_SIZE}" \\
  -e "plugins.security.disabled=false" \\
  -e "plugins.security.ssl.http.enabled=false" \\
  -e "plugins.security.ssl.transport.enabled=false" \\
  -e "plugins.security.authcz.admin_dn=CN=admin" \\
  -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_PASSWORD}" \\
  -e "DISABLE_INSTALL_DEMO_CONFIG=true" \\
  -v opensearch-data:/usr/share/opensearch/data \\
  ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}
SCRIPT_EOF
fi

cat >> "$TEMP_SCRIPT" << 'SCRIPT_EOF'

echo "=== Waiting for container to start ==="
sleep 10

echo "=== Container Status ==="
sudo docker ps -a | grep opensearch || echo "Container not found"

echo "=== Checking port 9200 ==="
sudo netstat -tlnp 2>/dev/null | grep ':9200 ' || sudo ss -tlnp 2>/dev/null | grep ':9200 ' || echo "Port 9200 not listening"

echo "=== Container Logs (last 20 lines) ==="
sudo docker logs opensearch --tail 20 2>&1 || echo "Cannot get logs"

echo "=== Testing health endpoint ==="
sleep 5
SCRIPT_EOF

if [ "$SECURITY_DISABLED" = "true" ]; then
  echo 'curl -f http://localhost:9200/_cluster/health && echo "Health check passed" || echo "Health check failed"' >> "$TEMP_SCRIPT"
else
  echo "curl -u admin:${OPENSEARCH_PASSWORD} -f http://localhost:9200/_cluster/health && echo 'Health check passed' || echo 'Health check failed'" >> "$TEMP_SCRIPT"
fi

# Read the script and send it via SSM
echo "Sending SSM command to fix Docker and start OpenSearch..."
SCRIPT_CONTENT=$(cat "$TEMP_SCRIPT")

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[$(echo "$SCRIPT_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')]" \
  --output-s3-bucket-name "shelfshack-dev-logs" \
  --output-s3-key-prefix "ssm-commands" \
  --query 'Command.CommandId' \
  --output text 2>/dev/null || echo "FAILED")

rm -f "$TEMP_SCRIPT"

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "FAILED" ] || [ "$COMMAND_ID" = "None" ]; then
  echo ""
  echo "ERROR: Could not send SSM command. Please check:"
  echo "1. SSM agent is running on the instance"
  echo "2. Instance has internet access or VPC endpoints configured"
  echo "3. IAM role has SSM permissions"
  echo ""
  echo "Alternative: Recreate the instance with fixed user_data:"
  echo "  terraform taint module.opensearch_ec2[0].aws_instance.opensearch"
  echo "  terraform apply -var-file=terraform.tfvars"
  exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting 30 seconds for command to complete..."
sleep 30

echo ""
echo "=== COMMAND OUTPUT ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null || echo "Error retrieving output"

echo ""
echo "=== ERRORS (if any) ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null || echo "No errors"

echo ""
echo "=== NEXT STEPS ==="
echo "1. Wait 1-2 minutes for OpenSearch to fully initialize"
echo "2. Run diagnostic script: ./diagnose_opensearch_complete.sh"
echo "3. Check ECS logs for connection success"
