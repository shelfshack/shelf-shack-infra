#!/bin/bash
# Fix the OpenSearch container that's stuck restarting

set -e

SCRIPT_DIR="$(SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/envs/dev" cd "$(dirname "$0")"cd "$(dirname "$0")" pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/envs/dev"cd "$(dirname "$0")" pwd)"
cd "$REPO_ROOT/envs/dev"

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null || echo "")
if [ -z "$INSTANCE_ID" ]; then
  echo "ERROR: Could not get instance ID"
  exit 1
fi

echo "=== FIXING OPENSEARCH CONTAINER ==="
echo "Instance ID: $INSTANCE_ID"
echo ""

# Check security setting
if grep -q "opensearch_ec2_security_disabled.*=.*true" terraform.tfvars 2>/dev/null; then
  SECURITY_DISABLED=true
  echo "Security: DISABLED"
else
  SECURITY_DISABLED=false
  OPENSEARCH_PASSWORD=$(grep "opensearch_ec2_admin_password" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "OpenSearch@2024!")
  echo "Security: ENABLED"
fi

# Get configuration from tfvars or use defaults
OPENSEARCH_IMAGE=$(grep "opensearch_ec2_image" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "opensearchproject/opensearch")
OPENSEARCH_VERSION=$(grep "opensearch_ec2_version" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "latest")
JAVA_HEAP_SIZE=$(grep "opensearch_ec2_java_heap_size" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "512m")
OPENSEARCH_PASSWORD=$(grep "opensearch_ec2_admin_password" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "OpenSearch@2024!")

echo "Image: ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}"
echo "Java Heap: $JAVA_HEAP_SIZE"
echo ""

# Build the command based on security setting
if [ "$SECURITY_DISABLED" = "true" ]; then
  echo "Stopping and restarting container with security DISABLED..."
  DOCKER_CMD="sudo docker stop opensearch 2>/dev/null || true; sudo docker rm opensearch 2>/dev/null || true; sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e 'discovery.type=single-node' -e 'network.host=0.0.0.0' -e 'OPENSEARCH_JAVA_OPTS=-Xms${JAVA_HEAP_SIZE} -Xmx${JAVA_HEAP_SIZE}' -e 'plugins.security.disabled=true' -e 'DISABLE_SECURITY_PLUGIN=true' -e 'OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_PASSWORD}' -e 'DISABLE_INSTALL_DEMO_CONFIG=true' -v opensearch-data:/usr/share/opensearch/data ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}"
else
  echo "Stopping and restarting container with security ENABLED..."
  DOCKER_CMD="sudo docker stop opensearch 2>/dev/null || true; sudo docker rm opensearch 2>/dev/null || true; sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e 'discovery.type=single-node' -e 'network.host=0.0.0.0' -e 'OPENSEARCH_JAVA_OPTS=-Xms${JAVA_HEAP_SIZE} -Xmx${JAVA_HEAP_SIZE}' -e 'plugins.security.disabled=false' -e 'plugins.security.ssl.http.enabled=false' -e 'plugins.security.ssl.transport.enabled=false' -e 'plugins.security.authcz.admin_dn=CN=admin' -e 'OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_PASSWORD}' -e 'DISABLE_INSTALL_DEMO_CONFIG=true' -v opensearch-data:/usr/share/opensearch/data ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}"
fi

echo "Sending SSM command..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"$DOCKER_CMD\", \"sleep 15\", \"sudo docker ps -a | grep opensearch\", \"sudo docker logs opensearch --tail 30 2>&1 || echo 'Cannot get logs'\", \"sleep 5\", \"curl -f http://localhost:9200/_cluster/health && echo 'Health check passed' || echo 'Health check failed'\"]" \
  --output-s3-bucket-name "shelfshack-dev-logs" \
  --output-s3-key-prefix "ssm-commands" \
  --query 'Command.CommandId' \
  --output text 2>/dev/null || echo "FAILED")

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "FAILED" ] || [ "$COMMAND_ID" = "None" ]; then
  echo "ERROR: Could not send SSM command"
  exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting 25 seconds for command to complete..."
sleep 25

echo ""
echo "=== OUTPUT ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null || echo "Error retrieving output"

echo ""
echo "=== ERRORS ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null || echo "None"

echo ""
echo "=== NEXT STEPS ==="
echo "1. Wait 1-2 minutes for OpenSearch to fully initialize"
echo "2. Run diagnostic: ./diagnose_opensearch_complete.sh"
echo "3. Check ECS logs for successful connections"
