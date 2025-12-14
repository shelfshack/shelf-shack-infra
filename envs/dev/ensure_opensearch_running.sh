#!/bin/bash
# Ensure OpenSearch container is running and accessible

set -e

cd "$(dirname "$0")"

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null || echo "")
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ]; then
  echo "ERROR: Could not get instance ID"
  exit 1
fi

echo "=== ENSURING OPENSEARCH IS RUNNING ==="
echo "Instance ID: $INSTANCE_ID"
echo "OpenSearch IP: $OPENSEARCH_IP"
echo ""

# Get configuration from tfvars or use defaults from module
if grep -q "opensearch_ec2_security_disabled.*=.*true" terraform.tfvars 2>/dev/null; then
  SECURITY_DISABLED=true
  echo "Security: DISABLED"
else
  SECURITY_DISABLED=false
  echo "Security: ENABLED"
fi

# Get values from tfvars (skip comments)
OPENSEARCH_IMAGE=$(grep "opensearch_ec2_image" terraform.tfvars 2>/dev/null | grep -v "^#" | cut -d'"' -f2)
OPENSEARCH_VERSION=$(grep "opensearch_ec2_version" terraform.tfvars 2>/dev/null | grep -v "^#" | cut -d'"' -f2)
JAVA_HEAP_SIZE=$(grep "opensearch_ec2_java_heap_size" terraform.tfvars 2>/dev/null | grep -v "^#" | cut -d'"' -f2)
OPENSEARCH_PASSWORD=$(grep "opensearch_ec2_admin_password" terraform.tfvars 2>/dev/null | grep -v "^#" | cut -d'"' -f2)

# Use defaults if not found
OPENSEARCH_IMAGE=${OPENSEARCH_IMAGE:-opensearchproject/opensearch}
OPENSEARCH_VERSION=${OPENSEARCH_VERSION:-2.11.0}
JAVA_HEAP_SIZE=${JAVA_HEAP_SIZE:-512m}
OPENSEARCH_PASSWORD=${OPENSEARCH_PASSWORD:-OpenSearch@2024!}

echo "Image: ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}"
echo "Java Heap: $JAVA_HEAP_SIZE"
echo ""

# Build docker command based on security setting
if [ "$SECURITY_DISABLED" = "true" ]; then
  DOCKER_RUN_CMD="sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e discovery.type=single-node -e network.host=0.0.0.0 -e OPENSEARCH_JAVA_OPTS=-Xms${JAVA_HEAP_SIZE} -Xmx${JAVA_HEAP_SIZE} -e plugins.security.disabled=true -e DISABLE_SECURITY_PLUGIN=true -e OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_PASSWORD} -e DISABLE_INSTALL_DEMO_CONFIG=true -v opensearch-data:/usr/share/opensearch/data ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}"
else
  DOCKER_RUN_CMD="sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e discovery.type=single-node -e network.host=0.0.0.0 -e OPENSEARCH_JAVA_OPTS=-Xms${JAVA_HEAP_SIZE} -Xmx${JAVA_HEAP_SIZE} -e plugins.security.disabled=false -e plugins.security.ssl.http.enabled=false -e plugins.security.ssl.transport.enabled=false -e plugins.security.authcz.admin_dn=CN=admin -e OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_PASSWORD} -e DISABLE_INSTALL_DEMO_CONFIG=true -v opensearch-data:/usr/share/opensearch/data ${OPENSEARCH_IMAGE}:${OPENSEARCH_VERSION}"
fi

# Build health check command
if [ "$SECURITY_DISABLED" = "true" ]; then
  HEALTH_CMD="curl -f http://localhost:9200/_cluster/health && echo ' - Health check PASSED' || echo ' - Health check FAILED'"
else
  HEALTH_CMD="curl -u admin:${OPENSEARCH_PASSWORD} -f http://localhost:9200/_cluster/health && echo ' - Health check PASSED' || echo ' - Health check FAILED'"
fi

echo "Sending SSM command to fix OpenSearch container..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    \"echo '=== Checking Docker ==='\",
    \"command -v docker >/dev/null || (sudo yum install -y docker && sudo systemctl start docker && sudo systemctl enable docker && sleep 5)\",
    \"echo '=== Stopping existing container ==='\",
    \"sudo docker stop opensearch 2>/dev/null || true\",
    \"sudo docker rm opensearch 2>/dev/null || true\",
    \"sleep 2\",
    \"echo '=== Starting OpenSearch container ==='\",
    \"${DOCKER_RUN_CMD}\",
    \"echo '=== Waiting for container to start ==='\",
    \"sleep 15\",
    \"echo '=== Container Status ==='\",
    \"sudo docker ps -a | grep opensearch || echo 'Container not found'\",
    \"echo '=== Checking port 9200 ==='\",
    \"(sudo netstat -tlnp 2>/dev/null | grep ':9200 ' || sudo ss -tlnp 2>/dev/null | grep ':9200 ') && echo 'Port 9200 is listening' || echo 'WARNING: Port 9200 is NOT listening'\",
    \"echo '=== Container Logs (last 30 lines) ==='\",
    \"sudo docker logs opensearch --tail 30 2>&1 || echo 'Cannot get logs'\",
    \"echo '=== Testing health endpoint ==='\",
    \"sleep 5\",
    \"${HEALTH_CMD}\"
  ]" \
  --output-s3-bucket-name "rentify-dev-logs" \
  --output-s3-key-prefix "ssm-commands" \
  --query 'Command.CommandId' \
  --output text 2>/dev/null || echo "FAILED")

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "FAILED" ] || [ "$COMMAND_ID" = "None" ]; then
  echo ""
  echo "ERROR: Could not send SSM command"
  echo ""
  echo "Alternative: Recreate the instance:"
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
echo "=== ERRORS ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null || echo "None"

echo ""
echo "=== NEXT STEPS ==="
echo "1. Wait 1-2 minutes for OpenSearch to fully initialize"
echo "2. Test connection: curl http://${OPENSEARCH_IP}:9200/_cluster/health"
echo "3. Check ECS logs for successful connections"
echo "4. If still failing, restart ECS service:"
echo "   aws ecs update-service --cluster rentify-dev-cluster --service rentify-dev-service --force-new-deployment"
