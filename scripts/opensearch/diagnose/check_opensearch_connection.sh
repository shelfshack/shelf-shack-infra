#!/bin/bash
# Check OpenSearch connection issues from ECS logs

set -e

SCRIPT_DIR="$(SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/envs/dev" cd "$(dirname "$0")"cd "$(dirname "$0")" pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/envs/dev"cd "$(dirname "$0")" pwd)"
cd "$REPO_ROOT/envs/dev"

CLUSTER=$(terraform output -raw cluster_name 2>/dev/null || echo "")
SERVICE=$(terraform output -raw service_name 2>/dev/null || echo "")
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host 2>/dev/null || echo "")

if [ -z "$CLUSTER" ]; then
  echo "ERROR: Could not get cluster name"
  exit 1
fi

LOG_GROUP="/ecs/${SERVICE%-service}"

echo "=== Checking OpenSearch Connection from ECS Logs ==="
echo "Cluster: $CLUSTER"
echo "Service: $SERVICE"
echo "OpenSearch IP: $OPENSEARCH_IP"
echo "Log Group: $LOG_GROUP"
echo ""

echo "=== Recent OpenSearch Connection Errors ==="
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "Connection refused" \
  --max-items 10 \
  --query 'events[*].[timestamp,message]' \
  --output text 2>/dev/null | head -20 || echo "No connection errors found or log group doesn't exist"

echo ""
echo "=== Recent OpenSearch Warnings ==="
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "OpenSearch" \
  --max-items 10 \
  --query 'events[*].[timestamp,message]' \
  --output text 2>/dev/null | head -20 || echo "No OpenSearch logs found"

echo ""
echo "=== Checking OpenSearch Container Status on EC2 ==="
INSTANCE_ID=$(terraform output -raw opensearch_ec2_instance_id 2>/dev/null || echo "")
if [ -n "$INSTANCE_ID" ]; then
  echo "Instance ID: $INSTANCE_ID"
  echo "Sending SSM command to check container..."
  
  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["echo \"=== DOCKER STATUS ===\"; sudo docker ps -a | grep opensearch || echo \"No opensearch container\"; echo \"\n=== PORT 9200 ===\"; sudo netstat -tlnp 2>/dev/null | grep 9200 || sudo ss -tlnp 2>/dev/null | grep 9200 || echo \"Port 9200 not listening\"; echo \"\n=== DOCKER LOGS (last 20) ===\"; sudo docker logs opensearch --tail 20 2>&1 || echo \"Cannot get logs\""]' \
    --output-s3-bucket-name "rentify-dev-logs" \
    --output-s3-key-prefix "ssm-commands" \
    --query 'Command.CommandId' \
    --output text 2>/dev/null || echo "FAILED")
  
  if [ -n "$COMMAND_ID" ] && [ "$COMMAND_ID" != "FAILED" ] && [ "$COMMAND_ID" != "None" ]; then
    echo "Command ID: $COMMAND_ID"
    echo "Waiting 10 seconds..."
    sleep 10
    
    echo ""
    echo "=== OUTPUT ==="
    aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' \
      --output text 2>/dev/null || echo "Error retrieving output"
  else
    echo "Could not send SSM command"
  fi
else
  echo "Could not get instance ID"
fi

echo ""
echo "=== Recommendations ==="
echo "1. If container is not running, recreate instance:"
echo "   terraform taint module.opensearch_ec2[0].aws_instance.opensearch"
echo "   terraform apply -var-file=terraform.tfvars"
echo ""
echo "2. Check ECS logs in real-time:"
echo "   aws logs tail $LOG_GROUP --follow"
echo ""
echo "3. Restart ECS service after OpenSearch is running:"
echo "   aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment"
