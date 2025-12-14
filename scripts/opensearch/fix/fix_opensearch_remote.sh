#!/bin/bash
# Fix OpenSearch using SSM send-command (non-interactive)

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "Error: Could not get instance ID"
  exit 1
fi

echo "=== Fixing OpenSearch on EC2 Instance ==="
echo "Instance ID: $INSTANCE_ID"
echo ""

echo "Step 1: Stopping and removing existing container..."
COMMAND_ID1=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "sudo docker stop opensearch 2>/dev/null || true",
    "sudo docker rm opensearch 2>/dev/null || true",
    "echo \"Old container removed\""
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID1"
sleep 5

echo ""
echo "Step 2: Starting new OpenSearch container..."
COMMAND_ID2=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e \"discovery.type=single-node\" -e \"OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m\" -e \"plugins.security.disabled=true\" -e \"OPENSEARCH_INITIAL_ADMIN_PASSWORD=OpenSearch@2024!\" -v opensearch-data:/usr/share/opensearch/data opensearchproject/opensearch:latest",
    "echo \"Container started. Container ID:\"",
    "sudo docker ps --filter name=opensearch --format \"{{.ID}}\""
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID2"
sleep 5

echo ""
echo "Step 3: Waiting 2 minutes for OpenSearch to initialize..."
sleep 120

echo ""
echo "Step 4: Checking OpenSearch health..."
COMMAND_ID3=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo \"=== Container Status ===\"",
    "sudo docker ps --filter name=opensearch",
    "echo \"\"",
    "echo \"=== OpenSearch Health ===\"",
    "curl -s http://localhost:9200/_cluster/health || echo \"Not ready yet\"",
    "echo \"\"",
    "echo \"=== Port Status ===\"",
    "sudo ss -tlnp | grep 9200 || echo \"Port not listening\"",
    "echo \"\"",
    "echo \"=== Recent Logs ===\"",
    "sudo docker logs opensearch --tail 10 2>&1"
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID3"
echo ""
echo "Waiting 10 seconds for results..."
sleep 10

echo ""
echo "=== Results ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID3" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text

echo ""
echo "=== Errors (if any) ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID3" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardErrorContent' \
  --output text

echo ""
echo "=== Done ==="
echo "If OpenSearch is healthy, your FastAPI service should be able to connect now."
