#!/bin/bash
# Deploy updated Lambda and check token validation

set -e

cd "$(dirname "$0")/.."

echo "🔍 WebSocket Token Validation Diagnostic & Deployment"
echo "====================================================="
echo ""

echo "1️⃣  Deploying updated Lambda with improved logging..."
terraform apply -var-file=terraform.tfvars -var="db_master_password=${DB_PASSWORD:-RohitSajud1234}" -auto-approve

echo ""
echo "2️⃣  Waiting for Lambda deployment..."
sleep 5

echo ""
echo "3️⃣  Checking recent Lambda logs for token validation errors..."
echo "   (Looking for 'Backend notification connect failed' or 'Invalid token')"
echo ""

# Check last 10 minutes of logs
aws logs filter-log-events \
  --log-group-name "/aws/lambda/shelfshack-prod-websocket-proxy" \
  --start-time $(($(date +%s) - 600))000 \
  --region us-east-1 \
  --filter-pattern "Backend notification connect failed OR Invalid token OR Notification connect" \
  --max-items 10 \
  --query 'events[*].message' \
  --output text 2>/dev/null | head -20 || echo "   No recent errors found"

echo ""
echo "4️⃣  To monitor Lambda logs in real-time:"
echo "   aws logs tail /aws/lambda/shelfshack-prod-websocket-proxy --follow --region us-east-1"
echo ""
echo "5️⃣  Next steps:"
echo "   - Try connecting from frontend (www.shelfshack.com)"
echo "   - Watch Lambda logs for:"
echo "     * 'Notification connect: connection_id=...'"
echo "     * 'Backend HTTP error: 401' (if token invalid)"
echo "     * 'Got user_id X for notification connection' (if successful)"
echo "     * 'Sending initial notifications to connection' (if payload received)"
echo ""
