#!/bin/bash
# Fix the current container by removing duplicate setting

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

echo "=== FIXING CURRENT CONTAINER ==="
echo "Instance ID: $INSTANCE_ID"
echo ""
echo "The container is restarting due to duplicate setting error."
echo "We'll stop it and restart with correct configuration."
echo ""

# Get configuration
JAVA_HEAP_SIZE=$(grep "opensearch_ec2_java_heap_size" terraform.tfvars 2>/dev/null | grep -v "^#" | cut -d'"' -f2)
JAVA_HEAP_SIZE=${JAVA_HEAP_SIZE:-256m}

OPENSEARCH_PASSWORD=$(grep "opensearch_ec2_admin_password" terraform.tfvars 2>/dev/null | grep -v "^#" | cut -d'"' -f2)
OPENSEARCH_PASSWORD=${OPENSEARCH_PASSWORD:-OpenSearch@2024!}

echo "Java Heap: $JAVA_HEAP_SIZE"
echo ""

# Build the fix command
COMMANDS="
echo '=== Stopping and removing container ==='
sudo docker stop opensearch 2>/dev/null || true
sudo docker rm opensearch 2>/dev/null || true
sleep 2

echo '=== Starting container with fixed configuration ==='
sudo docker run -d \\
  --name opensearch \\
  --restart unless-stopped \\
  -p 9200:9200 \\
  -p 9600:9600 \\
  -e 'discovery.type=single-node' \\
  -e 'network.host=0.0.0.0' \\
  -e 'OPENSEARCH_JAVA_OPTS=-Xms${JAVA_HEAP_SIZE} -Xmx${JAVA_HEAP_SIZE}' \\
  -e 'plugins.security.disabled=true' \\
  -e 'OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_PASSWORD}' \\
  -e 'DISABLE_INSTALL_DEMO_CONFIG=true' \\
  -v opensearch-data:/usr/share/opensearch/data \\
  opensearchproject/opensearch:2.11.0

echo '=== Waiting for container to start ==='
sleep 15

echo '=== Container Status ==='
sudo docker ps -a | grep opensearch

echo '=== Container Logs (last 30 lines) ==='
sudo docker logs opensearch --tail 30 2>&1 || echo 'Cannot get logs'

echo '=== Testing health ==='
sleep 10
curl -f http://localhost:9200/_cluster/health && echo ' - Health check PASSED' || echo ' - Health check FAILED'
"

echo "Sending SSM command..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[$(echo "$COMMANDS" | sed "s/'/\\\\'/g" | awk '{print "\""$0"\""}' | tr '\n' ',' | sed 's/,$//')]" \
  --output-s3-bucket-name "rentify-dev-logs" \
  --output-s3-key-prefix "ssm-commands" \
  --query 'Command.CommandId' \
  --output text 2>/dev/null || echo "FAILED")

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "FAILED" ] || [ "$COMMAND_ID" = "None" ]; then
  echo ""
  echo "ERROR: Could not send SSM command"
  echo ""
  echo "Manual fix via Session Manager:"
  echo "1. Go to EC2 Console → Connect → Session Manager"
  echo "2. Run these commands:"
  echo ""
  echo "sudo docker stop opensearch"
  echo "sudo docker rm opensearch"
  echo "sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e 'discovery.type=single-node' -e 'network.host=0.0.0.0' -e 'OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx256m' -e 'plugins.security.disabled=true' -e 'OPENSEARCH_INITIAL_ADMIN_PASSWORD=OpenSearch@2024!' -e 'DISABLE_INSTALL_DEMO_CONFIG=true' -v opensearch-data:/usr/share/opensearch/data opensearchproject/opensearch:2.11.0"
  exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting 25 seconds..."
sleep 25

echo ""
echo "=== OUTPUT ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null || echo "Error"

echo ""
echo "=== ERRORS ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null || echo "None"
