#!/bin/bash
# Restart OpenSearch - simple and direct

INSTANCE_ID="i-0c05f4a5b9c91d484"

echo "=== Restarting OpenSearch ==="
echo "Instance: $INSTANCE_ID"
echo ""

echo "Step 1: Stopping and removing old container..."
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo docker stop opensearch 2>/dev/null || true", "sudo docker rm opensearch 2>/dev/null || true", "echo Done"]' \
  --output text --query 'Command.CommandId' > /dev/null

echo "Waiting 5 seconds..."
sleep 5

echo ""
echo "Step 2: Starting new OpenSearch container with password..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e \"discovery.type=single-node\" -e \"OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m\" -e \"plugins.security.disabled=true\" -e \"OPENSEARCH_INITIAL_ADMIN_PASSWORD=OpenSearch@2024!\" -v opensearch-data:/usr/share/opensearch/data opensearchproject/opensearch:latest",
    "sleep 5",
    "sudo docker ps --filter name=opensearch --format \"Container: {{.Names}} Status: {{.Status}}\""
  ]' \
  --output text --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo ""
echo "Container is starting. This takes 1-2 minutes for OpenSearch to be ready."
echo ""
echo "Wait 2 minutes, then check status with:"
echo "  ./check_opensearch_final.sh"
echo ""
echo "Or check manually after 2 minutes:"
echo "  aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript --parameters 'commands=[\"curl http://localhost:9200/_cluster/health\"]' --output text --query 'Command.CommandId'"
