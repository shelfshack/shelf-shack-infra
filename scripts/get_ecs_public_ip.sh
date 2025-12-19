#!/bin/bash
# Script to get the public IP of the ECS service for HTTP API Gateway configuration

set -e

CLUSTER_NAME="${1:-shelfshack-dev-cluster}"
SERVICE_NAME="${2:-shelfshack-dev-service}"
REGION="${3:-us-east-1}"
CONTAINER_PORT="${4:-8000}"

echo "Getting ECS service public IP..."
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Region: $REGION"
echo ""

# Get the task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster "$CLUSTER_NAME" \
  --service-name "$SERVICE_NAME" \
  --region "$REGION" \
  --query 'taskArns[0]' \
  --output text)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
  echo "❌ Error: No running tasks found for service $SERVICE_NAME"
  echo ""
  echo "Please check:"
  echo "1. Is the ECS service running?"
  echo "2. Is the service name correct?"
  exit 1
fi

echo "Found task: $TASK_ARN"
echo ""

# Get ENI ID
ENI_ID=$(aws ecs describe-tasks \
  --cluster "$CLUSTER_NAME" \
  --tasks "$TASK_ARN" \
  --region "$REGION" \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text)

if [ -z "$ENI_ID" ] || [ "$ENI_ID" == "null" ]; then
  echo "❌ Error: Could not find network interface ID"
  exit 1
fi

echo "Network Interface ID: $ENI_ID"
echo ""

# Get public IP from ENI
PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids "$ENI_ID" \
  --region "$REGION" \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text)

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; then
  echo "❌ Error: Could not get public IP address"
  echo "The ECS task might not have a public IP assigned (check assign_public_ip setting)"
  exit 1
fi

echo "✅ ECS Service Public IP: $PUBLIC_IP"
echo ""
echo "Backend URL: http://${PUBLIC_IP}:${CONTAINER_PORT}"
echo ""
echo "Update your terraform.tfvars:"
echo "  http_api_backend_url = \"http://${PUBLIC_IP}:${CONTAINER_PORT}\""
echo ""
echo "Or update the Lambda function's BACKEND_URL environment variable:"
echo "  BACKEND_URL=http://${PUBLIC_IP}:${CONTAINER_PORT}"
echo ""

