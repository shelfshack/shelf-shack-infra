#!/bin/bash
# Comprehensive WebSocket connection diagnostic script

set -e

cd "$(dirname "$0")/.."

echo "🔍 WebSocket Connection Diagnostic"
echo "=================================="
echo ""

# 1. Check Terraform state for WebSocket API
echo "1️⃣  Checking Terraform WebSocket Configuration..."
WS_API_ID=$(terraform output -raw websocket_api_id 2>/dev/null || echo "NOT_FOUND")
WS_ENDPOINT=$(terraform output -raw websocket_api_endpoint 2>/dev/null || echo "NOT_FOUND")

if [ "$WS_API_ID" != "NOT_FOUND" ] && [ -n "$WS_API_ID" ]; then
  echo "   ✅ WebSocket API ID: $WS_API_ID"
  echo "   ✅ WebSocket Endpoint: $WS_ENDPOINT"
else
  echo "   ❌ WebSocket API not found in Terraform state"
  echo "   Run: terraform apply"
fi
echo ""

# 2. Check ECS Task Definition for WebSocket env vars
echo "2️⃣  Checking ECS Task Definition for WebSocket Environment Variables..."
CLUSTER="shelfshack-prod-cluster"
SERVICE="shelfshack-prod-service"

TASK_DEF_ARN=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region us-east-1 \
  --query 'services[0].taskDefinition' \
  --output text 2>/dev/null || echo "")

if [ -n "$TASK_DEF_ARN" ] && [ "$TASK_DEF_ARN" != "None" ]; then
  echo "   Task Definition: $TASK_DEF_ARN"
  
  # Get task definition details
  TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition "$TASK_DEF_ARN" \
    --region us-east-1 \
    --query 'taskDefinition.containerDefinitions[0].environment' \
    --output json 2>/dev/null || echo "[]")
  
  # Check for WebSocket env vars
  CONNECTIONS_TABLE=$(echo "$TASK_DEF" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for env in data:
        if env.get('name') == 'CONNECTIONS_TABLE':
            print(env.get('value', 'NOT_SET'))
            break
    else:
        print('NOT_SET')
except:
    print('NOT_SET')
" 2>/dev/null || echo "NOT_SET")
  
  WEBSOCKET_ENDPOINT=$(echo "$TASK_DEF" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for env in data:
        if env.get('name') == 'WEBSOCKET_API_ENDPOINT':
            print(env.get('value', 'NOT_SET'))
            break
    else:
        print('NOT_SET')
except:
    print('NOT_SET')
" 2>/dev/null || echo "NOT_SET")
  
  AWS_REGION_ENV=$(echo "$TASK_DEF" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for env in data:
        if env.get('name') == 'AWS_REGION':
            print(env.get('value', 'NOT_SET'))
            break
    else:
        print('NOT_SET')
except:
    print('NOT_SET')
" 2>/dev/null || echo "NOT_SET")
  
  echo "   CONNECTIONS_TABLE: $CONNECTIONS_TABLE"
  echo "   WEBSOCKET_API_ENDPOINT: $WEBSOCKET_ENDPOINT"
  echo "   AWS_REGION: $AWS_REGION_ENV"
  
  if [ "$CONNECTIONS_TABLE" != "NOT_SET" ] && [ "$WEBSOCKET_ENDPOINT" != "NOT_SET" ]; then
    echo "   ✅ WebSocket env vars are configured in ECS task definition"
  else
    echo "   ❌ WebSocket env vars are MISSING from ECS task definition"
    echo "   ⚠️  Run: terraform apply to update ECS service with WebSocket env vars"
  fi
else
  echo "   ❌ Could not get ECS service task definition"
fi
echo ""

# 3. Check Lambda function configuration
echo "3️⃣  Checking Lambda Function Configuration..."
LAMBDA_FUNC="shelfshack-prod-websocket-proxy"
LAMBDA_CONFIG=$(aws lambda get-function-configuration \
  --function-name "$LAMBDA_FUNC" \
  --region us-east-1 \
  --output json 2>/dev/null || echo "{}")

if [ "$LAMBDA_CONFIG" != "{}" ]; then
  BACKEND_URL=$(echo "$LAMBDA_CONFIG" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    env_vars = data.get('Environment', {}).get('Variables', {})
    print(env_vars.get('BACKEND_URL', 'NOT_SET'))
except:
    print('NOT_SET')
" 2>/dev/null || echo "NOT_SET")
  
  echo "   Lambda Function: $LAMBDA_FUNC"
  echo "   BACKEND_URL: $BACKEND_URL"
  echo "   ✅ Lambda function exists"
else
  echo "   ❌ Lambda function not found"
fi
echo ""

# 4. Check Amplify environment variables
echo "4️⃣  Checking Amplify Environment Variables..."
AMPLIFY_APP_ID="d26vv4xxnh3x3s"
AMPLIFY_BRANCH="main"

AMPLIFY_CONFIG=$(aws amplify get-branch \
  --app-id "$AMPLIFY_APP_ID" \
  --branch-name "$AMPLIFY_BRANCH" \
  --region us-east-1 \
  --output json 2>/dev/null || echo "{}")

if [ "$AMPLIFY_CONFIG" != "{}" ]; then
  WS_ENDPOINT_AMPLIFY=$(echo "$AMPLIFY_CONFIG" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    env_vars = data.get('branch', {}).get('environmentVariables', {})
    print(env_vars.get('WS_API_ENDPOINT_PRODUCTION', 'NOT_SET'))
except:
    print('NOT_SET')
" 2>/dev/null || echo "NOT_SET")
  
  echo "   WS_API_ENDPOINT_PRODUCTION: $WS_ENDPOINT_AMPLIFY"
  
  if [ "$WS_ENDPOINT_AMPLIFY" != "NOT_SET" ]; then
    echo "   ✅ Amplify has WebSocket endpoint configured"
  else
    echo "   ❌ Amplify WebSocket endpoint is NOT SET"
    echo "   ⚠️  Run: terraform apply to update Amplify env vars"
  fi
else
  echo "   ❌ Could not get Amplify configuration"
fi
echo ""

# 5. Check recent Lambda logs for connection errors
echo "5️⃣  Checking Recent Lambda Logs (last 5 minutes)..."
LOG_GROUP="/aws/lambda/shelfshack-prod-websocket-proxy"
START_TIME=$(date -u -v-5M +%s)000 2>/dev/null || $(date -u -d '5 minutes ago' +%s)000

aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --start-time "$START_TIME" \
  --region us-east-1 \
  --filter-pattern "ERROR" \
  --max-items 10 \
  --query 'events[*].message' \
  --output text 2>/dev/null | head -5 || echo "   No recent errors found (or log group doesn't exist)"

echo ""
echo "✅ Diagnostic complete!"
echo ""
echo "📋 Summary:"
echo "   - If ECS env vars are missing: Run 'terraform apply'"
echo "   - If Amplify endpoint is missing: Run 'terraform apply'"
echo "   - Check browser console for WebSocket connection errors"
echo "   - Check Lambda CloudWatch logs for $connect event handling"
