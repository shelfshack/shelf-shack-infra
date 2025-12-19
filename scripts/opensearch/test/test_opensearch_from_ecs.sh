#!/bin/bash
# Test OpenSearch connection from inside ECS container

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

if [ -z "$CLUSTER" ] || [ -z "$SERVICE" ]; then
  echo "ERROR: Could not get cluster or service name"
  exit 1
fi

echo "=== Testing OpenSearch from ECS Container ==="
echo "Cluster: $CLUSTER"
echo "Service: $SERVICE"
echo "OpenSearch IP: $OPENSEARCH_IP"
echo ""

# Get a running task
echo "Getting running task..."
TASK_ARN=$(aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text 2>/dev/null || echo "")

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
  echo "ERROR: No running tasks found"
  echo "Make sure the ECS service has at least one running task"
  exit 1
fi

echo "Task ARN: $TASK_ARN"
echo ""

# Get container name
CONTAINER_NAME=$(aws ecs describe-tasks \
  --cluster "$CLUSTER" \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].name' \
  --output text 2>/dev/null || echo "")

if [ -z "$CONTAINER_NAME" ]; then
  CONTAINER_NAME=$(terraform output -raw service_name 2>/dev/null | sed 's/-service$//' || echo "shelfshack-dev")
fi

echo "Container: $CONTAINER_NAME"
echo ""

# Check if execute command is enabled
echo "Testing OpenSearch connection from ECS container..."
echo ""

# Method 1: Use ECS Exec (if enabled)
echo "Method 1: Using ECS Exec (interactive)"
echo "Run this command to get an interactive shell:"
echo ""
echo "aws ecs execute-command \\"
echo "  --cluster $CLUSTER \\"
echo "  --task $TASK_ARN \\"
echo "  --container $CONTAINER_NAME \\"
echo "  --interactive \\"
echo "  --command \"/bin/bash\""
echo ""
echo "Then inside the container, run:"
echo "  curl http://${OPENSEARCH_IP}:9200/_cluster/health"
echo ""

# Method 2: Use send-command via SSM (if ECS Exec not enabled)
echo "Method 2: Using SSM send-command (non-interactive)"
echo "This will execute the curl command directly:"
echo ""

COMMAND_ID=$(aws ssm send-command \
  --targets "Key=taskArn,Values=$TASK_ARN" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"echo 'Testing OpenSearch connection...'\", \"curl -v http://${OPENSEARCH_IP}:9200/_cluster/health\", \"echo ''\", \"echo 'Checking environment variables:'\", \"env | grep OPENSEARCH\"]" \
  --query 'Command.CommandId' \
  --output text 2>/dev/null || echo "FAILED")

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "FAILED" ]; then
  echo "SSM send-command not available. Use ECS Exec method above."
  echo ""
  echo "To enable ECS Exec, ensure:"
  echo "1. enable_execute_command = true in ECS service"
  echo "2. Task role has SSM permissions"
  echo ""
else
  echo "Command ID: $COMMAND_ID"
  echo "Waiting 10 seconds..."
  sleep 10
  
  echo ""
  echo "=== OUTPUT ==="
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$TASK_ARN" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null || echo "Error retrieving output"
  
  echo ""
  echo "=== ERRORS ==="
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$TASK_ARN" \
    --query 'StandardErrorContent' \
    --output text 2>/dev/null || echo "None"
fi

echo ""
echo "=== Alternative: Direct ECS Exec Command ==="
echo "You can also run this directly:"
echo ""
echo "aws ecs execute-command \\"
echo "  --cluster $CLUSTER \\"
echo "  --task $TASK_ARN \\"
echo "  --container $CONTAINER_NAME \\"
echo "  --interactive \\"
echo "  --command \"curl http://${OPENSEARCH_IP}:9200/_cluster/health\""
