#!/bin/bash
# Quick check with proper instance ID handling

INSTANCE_ID="i-0c05f4a5b9c91d484"  # Known instance ID

echo "=== OpenSearch Status Check ==="
echo "Instance: $INSTANCE_ID"
echo ""

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "sudo docker ps -a --filter name=opensearch",
    "echo \"---\"",
    "curl -s http://localhost:9200/_cluster/health || echo \"Not ready\"",
    "echo \"---\"",
    "sudo docker logs opensearch --tail 10 2>&1 || echo \"No logs\""
  ]' \
  --output text \
  --query 'Command.CommandId')

echo "Command sent. ID: $COMMAND_ID"
echo "Waiting 20 seconds for results..."
sleep 20

echo ""
echo "=== Results ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text

echo ""
