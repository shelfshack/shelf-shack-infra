#!/bin/bash
# Script to manually update WebSocket Lambda's BACKEND_URL if it's stale

set -e

cd "$(dirname "$0")/.."

echo "🔧 Updating WebSocket Lambda BACKEND_URL..."
echo ""

# Get current ECS task public IP
echo "1. Getting current ECS task public IP..."
CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "shelfshack-prod-cluster")
SERVICE=$(terraform output -raw ecs_service_name 2>/dev/null || echo "shelfshack-prod-service")

TASK_ARN=$(aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text \
  --region us-east-1 2>/dev/null)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
  echo "❌ No running ECS tasks found"
  exit 1
fi

ENI_ID=$(aws ecs describe-tasks \
  --cluster "$CLUSTER" \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text \
  --region us-east-1 2>/dev/null)

PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids "$ENI_ID" \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text \
  --region us-east-1 2>/dev/null)

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; then
  echo "❌ No public IP found for ECS task"
  exit 1
fi

CONTAINER_PORT=$(grep 'container_port' terraform.tfvars | grep -o '[0-9]\+' | head -1 || echo "8000")
NEW_BACKEND_URL="http://${PUBLIC_IP}:${CONTAINER_PORT}"

echo "   Current ECS Task IP: $PUBLIC_IP"
echo "   New BACKEND_URL: $NEW_BACKEND_URL"
echo ""

# Get current Lambda BACKEND_URL
LAMBDA_FUNC="shelfshack-prod-websocket-proxy"
CURRENT_BACKEND_URL=$(aws lambda get-function-configuration \
  --function-name "$LAMBDA_FUNC" \
  --region us-east-1 \
  --query 'Environment.Variables.BACKEND_URL' \
  --output text 2>/dev/null || echo "")

echo "2. Current Lambda BACKEND_URL: $CURRENT_BACKEND_URL"
echo ""

if [ "$CURRENT_BACKEND_URL" == "$NEW_BACKEND_URL" ]; then
  echo "✅ Lambda BACKEND_URL is already up to date!"
  exit 0
fi

# Update Lambda environment variable
echo "3. Updating Lambda BACKEND_URL..."
aws lambda update-function-configuration \
  --function-name "$LAMBDA_FUNC" \
  --environment "Variables={BACKEND_URL=$NEW_BACKEND_URL,CONNECTIONS_TABLE=$(aws lambda get-function-configuration --function-name "$LAMBDA_FUNC" --region us-east-1 --query 'Environment.Variables.CONNECTIONS_TABLE' --output text),API_GATEWAY_ENDPOINT=$(aws lambda get-function-configuration --function-name "$LAMBDA_FUNC" --region us-east-1 --query 'Environment.Variables.API_GATEWAY_ENDPOINT' --output text)}" \
  --region us-east-1 >/dev/null

echo "✅ Lambda BACKEND_URL updated successfully!"
echo ""
echo "⚠️  Note: This is a temporary fix. Run 'terraform apply' to ensure the configuration is properly managed by Terraform."
