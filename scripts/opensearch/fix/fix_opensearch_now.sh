#!/bin/bash
# Immediate fix for OpenSearch - stops, removes, and recreates container

INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
  echo "Error: Could not get instance ID"
  exit 1
fi

echo "=== Fixing OpenSearch on EC2 ==="
echo "Instance: $INSTANCE_ID"
echo ""

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "set -e",
    "echo \"[$(date)] Stopping existing container...\"",
    "sudo docker stop opensearch 2>/dev/null || true",
    "sudo docker rm opensearch 2>/dev/null || true",
    "echo \"[$(date)] Starting new OpenSearch container...\"",
    "sudo docker run -d --name opensearch --restart unless-stopped -p 9200:9200 -p 9600:9600 -e \"discovery.type=single-node\" -e \"OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m\" -e \"plugins.security.disabled=true\" -e \"OPENSEARCH_INITIAL_ADMIN_PASSWORD=OpenSearch@2024!\" -v opensearch-data:/usr/share/opensearch/data opensearchproject/opensearch:latest",
    "echo \"[$(date)] Container started. Waiting 90 seconds for OpenSearch to initialize...\"",
    "sleep 90",
    "echo \"[$(date)] Checking OpenSearch health...\"",
    "for i in {1..12}; do",
    "  if curl -sf http://localhost:9200/_cluster/health > /dev/null 2>&1; then",
    "    echo \"[$(date)] ✓ OpenSearch is HEALTHY!\"",
    "    curl -s http://localhost:9200/_cluster/health",
    "    echo \"\"",
    "    echo \"[$(date)] ✓ Port 9200 is listening:\"",
    "    sudo ss -tlnp | grep 9200",
    "    exit 0",
    "  fi",
    "  echo \"[$(date)] Waiting... ($i/12 - ~$((i*15)) seconds elapsed)\"",
    "  sleep 15",
    "done",
    "echo \"[$(date)] ⚠ OpenSearch may still be starting. Check logs:\"",
    "sudo docker logs opensearch --tail 20"
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo ""
echo "This will take ~3 minutes. Monitoring progress..."
echo ""

# Poll for completion with progress
for i in {1..40}; do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Pending")
  
  if [ "$STATUS" = "Success" ]; then
    echo ""
    echo "=== ✓ SUCCESS ==="
    aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' \
      --output text
    break
  elif [ "$STATUS" = "Failed" ]; then
    echo ""
    echo "=== ✗ FAILED ==="
    aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query '[StandardOutputContent,StandardErrorContent]' \
      --output text
    break
  fi
  
  # Show progress every 10 seconds
  if [ $((i % 2)) -eq 0 ]; then
    echo -n "."
  fi
  sleep 5
done

echo ""
echo ""
echo "=== Verification ==="
echo "To verify OpenSearch is working:"
echo "  aws ssm start-session --target $INSTANCE_ID"
echo "  curl http://localhost:9200/_cluster/health"
