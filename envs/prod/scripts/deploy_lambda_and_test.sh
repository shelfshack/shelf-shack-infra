#!/bin/bash
# Deploy updated Lambda function and test WebSocket connection

set -e

cd "$(dirname "$0")/.."

echo "🚀 Deploying Updated Lambda Function..."
echo ""

# Step 1: Run Terraform apply to deploy updated Lambda
echo "1️⃣  Running Terraform apply to deploy Lambda with improved logging..."
terraform apply -var-file=terraform.tfvars -var="db_master_password=${DB_PASSWORD:-RohitSajud1234}" -auto-approve

echo ""
echo "2️⃣  Waiting for Lambda deployment to complete..."
sleep 5

echo ""
echo "3️⃣  Checking Lambda function version..."
LAMBDA_FUNC="shelfshack-prod-websocket-proxy"
LAMBDA_VERSION=$(aws lambda get-function \
  --function-name "$LAMBDA_FUNC" \
  --region us-east-1 \
  --query 'Configuration.LastModified' \
  --output text 2>/dev/null || echo "")

if [ -n "$LAMBDA_VERSION" ]; then
  echo "   ✅ Lambda function updated at: $LAMBDA_VERSION"
else
  echo "   ⚠️  Could not verify Lambda update"
fi

echo ""
echo "4️⃣  Monitoring Lambda logs for WebSocket connections..."
echo "   (Press Ctrl+C to stop monitoring)"
echo ""
echo "   Try connecting from the frontend now, and watch for:"
echo "   - 'Connection: type=notification'"
echo "   - 'Notification connect: connection_id=...'"
echo "   - 'Backend notification connect failed' or 'Got user_id'"
echo ""

# Tail Lambda logs
aws logs tail "/aws/lambda/$LAMBDA_FUNC" \
  --follow \
  --region us-east-1 \
  --filter-pattern "Connection: type=notification OR Notification connect OR Backend notification" \
  2>/dev/null || {
  echo "   ⚠️  Could not tail logs. Check manually:"
  echo "   aws logs tail /aws/lambda/$LAMBDA_FUNC --follow --region us-east-1"
}
