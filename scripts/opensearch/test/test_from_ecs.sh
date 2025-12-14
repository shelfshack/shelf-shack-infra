#!/bin/bash
# Test OpenSearch connection from ECS task

CLUSTER=$(terraform output -raw cluster_name)
SERVICE=$(terraform output -raw service_name)
OPENSEARCH_IP=$(terraform output -raw opensearch_ec2_host)

echo "=== Testing OpenSearch from ECS ==="
echo "Cluster: $CLUSTER"
echo "Service: $SERVICE"
echo "OpenSearch IP: $OPENSEARCH_IP"
echo ""

# Get a running task
TASK_ARN=$(aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
  echo "No running tasks found. Start the ECS service first."
  exit 1
fi

TASK_ID=$(echo "$TASK_ARN" | cut -d/ -f3)
echo "Task ID: $TASK_ID"
echo ""

echo "Testing connection to OpenSearch..."
aws ecs execute-command \
  --cluster "$CLUSTER" \
  --task "$TASK_ID" \
  --container "$SERVICE" \
  --interactive \
  --command "curl -v http://$OPENSEARCH_IP:9200/_cluster/health"
