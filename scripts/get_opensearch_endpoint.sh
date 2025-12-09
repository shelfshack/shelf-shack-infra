#!/bin/bash
# Script to get OpenSearch container service endpoint

set -e

CLUSTER_NAME="${1:-rentify-dev-cluster}"
SERVICE_NAME="${2:-rentify-dev-opensearch-service}"
REGION="${3:-us-east-1}"

echo "Getting OpenSearch service endpoint..."
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
  echo "1. Is the OpenSearch service running?"
  echo "2. Is the service name correct?"
  exit 1
fi

echo "Found task: $TASK_ARN"
echo ""

# Get ENI ID directly using AWS CLI query
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

# Get private IP from ENI
PRIVATE_IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids "$ENI_ID" \
  --region "$REGION" \
  --query 'NetworkInterfaces[0].PrivateIpAddress' \
  --output text)

if [ -z "$PRIVATE_IP" ] || [ "$PRIVATE_IP" == "None" ]; then
  echo "❌ Error: Could not get private IP address"
  exit 1
fi

echo "✅ OpenSearch Endpoint: $PRIVATE_IP"
echo ""
echo "Update your backend environment variables:"
echo "  OPENSEARCH_HOST=$PRIVATE_IP"
echo "  OPENSEARCH_PORT=9200"
echo "  OPENSEARCH_USE_SSL=false"
echo "  OPENSEARCH_VERIFY_CERTS=false"
echo ""







