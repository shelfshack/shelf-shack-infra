#!/bin/bash
# Complete fix for OpenSearch - stops, removes, and recreates with proper config

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "Error: Could not get OpenSearch EC2 instance ID"
  exit 1
fi

echo "=== Complete OpenSearch Fix ==="
echo "Instance ID: $INSTANCE_ID"
echo "This will:"
echo "  1. Stop and remove existing container"
echo "  2. Start new container with password"
echo "  3. Wait for OpenSearch to be ready"
echo "  4. Verify health"
echo ""

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "set -e",
    "echo \"Stopping existing OpenSearch container...\"",
    "sudo docker stop opensearch 2>/dev/null || true",
    "sudo docker rm opensearch 2>/dev/null || true",
    "echo \"Removed old container\"",
    "echo \"\"",
    "echo \"Starting new OpenSearch container with password...\"",
    "sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e \"discovery.type=single-node\" -e \"OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m\" -e \"plugins.security.disabled=true\" -e \"OPENSEARCH_INITIAL_ADMIN_PASSWORD=OpenSearch@2024!\" -v opensearch-data:/usr/share/opensearch/data opensearchproject/opensearch:latest",
    "echo \"Container started, waiting for OpenSearch to initialize (this takes 1-2 minutes)...\"",
    "sleep 30",
    "for i in {1..24}; do",
    "  if curl -sf http://localhost:9200/_cluster/health > /dev/null 2>&1; then",
    "    echo \"\"",
    "    echo \"✓ OpenSearch is healthy!\"",
    "    curl -s http://localhost:9200/_cluster/health | head -10",
    "    exit 0",
    "  fi",
    "  echo \"Waiting for OpenSearch... ($i/24 - ~$((i*5)) seconds)\"",
    "  sleep 5",
    "done",
    "echo \"\"",
    "echo \"⚠ OpenSearch may still be starting. Check logs with: sudo docker logs opensearch\"",
    "curl -s http://localhost:9200/_cluster/health || echo \"Not ready yet\""
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo ""
echo "This will take 2-3 minutes. You can check status with:"
echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $INSTANCE_ID"
echo ""
echo "Or wait and I'll show the results..."
sleep 5

# Poll for completion
for i in {1..30}; do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'Status' \
    --output text 2>/dev/null)
  
  if [ "$STATUS" = "Success" ] || [ "$STATUS" = "Failed" ]; then
    echo ""
    echo "=== Command Completed ==="
    echo ""
    echo "Output:"
    aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' \
      --output text
    echo ""
    echo "Errors (if any):"
    aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardErrorContent' \
      --output text
    break
  fi
  echo -n "."
  sleep 5
done

echo ""
echo ""
echo "=== Verification ==="
echo "To verify OpenSearch is working, run:"
echo "  ./diagnose_opensearch.sh"
echo ""
echo "Or connect and test manually:"
echo "  aws ssm start-session --target $INSTANCE_ID"
echo "  curl http://localhost:9200/_cluster/health"
