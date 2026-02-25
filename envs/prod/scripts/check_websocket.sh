#!/bin/bash
# Script to check WebSocket configuration in production

set -e

cd "$(dirname "$0")/.."

echo "🔍 Checking WebSocket Configuration..."
echo ""

# Get WebSocket API ID from AWS directly
WS_API_ID=$(aws apigatewayv2 get-apis --region us-east-1 --query "Items[?Name=='shelfshack-prod-websocket'].ApiId" --output text 2>/dev/null | head -1 || echo "NOT_FOUND")
echo "📡 WebSocket API ID: $WS_API_ID"

if [ "$WS_API_ID" != "NOT_FOUND" ] && [ -n "$WS_API_ID" ]; then
  WS_ENDPOINT="wss://${WS_API_ID}.execute-api.us-east-1.amazonaws.com/production"
  echo "🔗 WebSocket Endpoint: $WS_ENDPOINT"
else
  echo "🔗 WebSocket Endpoint: NOT_FOUND"
  WS_ENDPOINT="NOT_FOUND"
fi

# Get Lambda function name
LAMBDA_FUNC="shelfshack-prod-websocket-proxy"
echo "⚡ Lambda Function: $LAMBDA_FUNC"

# Check Lambda environment variables
if [ "$LAMBDA_FUNC" != "NOT_FOUND" ]; then
  echo ""
  echo "🔧 Lambda Environment Variables:"
  LAMBDA_CONFIG=$(aws lambda get-function-configuration \
    --function-name "$LAMBDA_FUNC" \
    --region us-east-1 \
    --query 'Environment.Variables' \
    --output json 2>/dev/null)
  
  if [ -n "$LAMBDA_CONFIG" ]; then
    echo "$LAMBDA_CONFIG" | python3 -m json.tool 2>/dev/null || echo "$LAMBDA_CONFIG"
    echo ""
    echo "📋 Key Variables:"
    echo "$LAMBDA_CONFIG" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(f\"  BACKEND_URL: {data.get('BACKEND_URL', 'NOT SET')}\")
    print(f\"  CONNECTIONS_TABLE: {data.get('CONNECTIONS_TABLE', 'NOT SET')}\")
    print(f\"  API_GATEWAY_ENDPOINT: {data.get('API_GATEWAY_ENDPOINT', 'NOT SET')}\")
except:
    pass
" 2>/dev/null || echo "  (Could not parse)"
  else
    echo "Failed to get Lambda config"
  fi
fi

# Check Amplify environment variables
AMPLIFY_APP_ID=$(grep 'amplify_app_id' terraform.tfvars | grep -o '"[^"]*"' | tr -d '"' | head -1)
AMPLIFY_BRANCH=$(grep 'amplify_prod_branch_name' terraform.tfvars | grep -o '"[^"]*"' | tr -d '"' | head -1 || echo "main")
if [ -n "$AMPLIFY_APP_ID" ]; then
  echo ""
  echo "🌐 Amplify Environment Variables (App: $AMPLIFY_APP_ID, Branch: $AMPLIFY_BRANCH):"
  AMPLIFY_CONFIG=$(aws amplify get-branch \
    --app-id "$AMPLIFY_APP_ID" \
    --branch-name "$AMPLIFY_BRANCH" \
    --region us-east-1 \
    --query 'branch.environmentVariables' \
    --output json 2>/dev/null)
  
  if [ -n "$AMPLIFY_CONFIG" ]; then
    echo "$AMPLIFY_CONFIG" | python3 -m json.tool 2>/dev/null || echo "$AMPLIFY_CONFIG"
    echo ""
    echo "📋 Key Variables:"
    echo "$AMPLIFY_CONFIG" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(f\"  WS_API_ENDPOINT_PRODUCTION: {data.get('WS_API_ENDPOINT_PRODUCTION', 'NOT SET')}\")
    print(f\"  API_BASE_URL_PRODUCTION: {data.get('API_BASE_URL_PRODUCTION', 'NOT SET')}\")
except:
    pass
" 2>/dev/null || echo "  (Could not parse)"
  else
    echo "Failed to get Amplify config"
  fi
fi

echo ""
echo "✅ Check complete!"
