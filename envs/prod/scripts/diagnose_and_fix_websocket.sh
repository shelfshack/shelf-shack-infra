#!/bin/bash
# Comprehensive WebSocket diagnostic and fix script

set -e

cd "$(dirname "$0")/.."

echo "🔍 WebSocket Connection Diagnostic & Fix"
echo "========================================"
echo ""

# Step 1: Check if Terraform apply was run
echo "1️⃣  Checking if Terraform apply was run..."
if terraform state list 2>/dev/null | grep -q "aws_ecs_service"; then
  echo "   ✅ Terraform state exists"
else
  echo "   ❌ Terraform state not found - run 'terraform init' first"
  exit 1
fi

# Step 2: Check ECS Task Definition for WebSocket env vars
echo ""
echo "2️⃣  Checking ECS Task Definition..."
CLUSTER="shelfshack-prod-cluster"
SERVICE="shelfshack-prod-service"

TASK_DEF_ARN=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region us-east-1 \
  --query 'services[0].taskDefinition' \
  --output text 2>/dev/null || echo "")

if [ -z "$TASK_DEF_ARN" ] || [ "$TASK_DEF_ARN" == "None" ]; then
  echo "   ❌ Could not get ECS service - check if service exists"
  exit 1
fi

echo "   Task Definition: $TASK_DEF_ARN"

# Get environment variables
TASK_DEF_JSON=$(aws ecs describe-task-definition \
  --task-definition "$TASK_DEF_ARN" \
  --region us-east-1 \
  --output json 2>/dev/null)

CONNECTIONS_TABLE=$(echo "$TASK_DEF_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    envs = data['taskDefinition']['containerDefinitions'][0].get('environment', [])
    for env in envs:
        if env.get('name') == 'CONNECTIONS_TABLE':
            print(env.get('value', ''))
            break
    else:
        print('')
except:
    print('')
")

WEBSOCKET_ENDPOINT=$(echo "$TASK_DEF_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    envs = data['taskDefinition']['containerDefinitions'][0].get('environment', [])
    for env in envs:
        if env.get('name') == 'WEBSOCKET_API_ENDPOINT':
            print(env.get('value', ''))
            break
    else:
        print('')
except:
    print('')
")

if [ -z "$CONNECTIONS_TABLE" ] || [ -z "$WEBSOCKET_ENDPOINT" ]; then
  echo "   ❌ WebSocket env vars are MISSING from ECS task definition"
  echo ""
  echo "   🔧 FIX: Run Terraform apply to add WebSocket env vars:"
  echo "      terraform apply -var-file=terraform.tfvars -var='db_master_password=YOUR_PASSWORD' -auto-approve"
  echo ""
  echo "   This will:"
  echo "   1. Update ECS service with CONNECTIONS_TABLE, WEBSOCKET_API_ENDPOINT, AWS_REGION"
  echo "   2. Trigger a new task deployment with the correct environment variables"
  exit 1
else
  echo "   ✅ CONNECTIONS_TABLE: $CONNECTIONS_TABLE"
  echo "   ✅ WEBSOCKET_API_ENDPOINT: $WEBSOCKET_ENDPOINT"
  echo "   ✅ WebSocket env vars are configured"
fi

# Step 3: Check Lambda function
echo ""
echo "3️⃣  Checking Lambda Function..."
LAMBDA_FUNC="shelfshack-prod-websocket-proxy"
LAMBDA_EXISTS=$(aws lambda get-function \
  --function-name "$LAMBDA_FUNC" \
  --region us-east-1 \
  --query 'Configuration.FunctionName' \
  --output text 2>/dev/null || echo "")

if [ -z "$LAMBDA_EXISTS" ]; then
  echo "   ❌ Lambda function not found"
  exit 1
fi

LAMBDA_BACKEND_URL=$(aws lambda get-function-configuration \
  --function-name "$LAMBDA_FUNC" \
  --region us-east-1 \
  --query 'Environment.Variables.BACKEND_URL' \
  --output text 2>/dev/null || echo "")

echo "   ✅ Lambda function exists"
echo "   BACKEND_URL: $LAMBDA_BACKEND_URL"

# Step 4: Check if backend is reachable
echo ""
echo "4️⃣  Testing Backend Connectivity..."
if [ -n "$LAMBDA_BACKEND_URL" ]; then
  # Extract IP from BACKEND_URL (format: http://IP:PORT)
  BACKEND_IP=$(echo "$LAMBDA_BACKEND_URL" | sed -E 's|http://([^:]+):.*|\1|')
  BACKEND_PORT=$(echo "$LAMBDA_BACKEND_URL" | sed -E 's|http://[^:]+:([0-9]+).*|\1|')
  
  echo "   Testing: $BACKEND_IP:$BACKEND_PORT"
  
  # Test if backend is reachable
  if timeout 3 bash -c "echo > /dev/tcp/$BACKEND_IP/$BACKEND_PORT" 2>/dev/null; then
    echo "   ✅ Backend is reachable"
  else
    echo "   ⚠️  Backend might not be reachable (this could be normal if in private subnet)"
  fi
fi

# Step 5: Check Lambda logs for recent errors
echo ""
echo "5️⃣  Checking Recent Lambda Logs (last 10 minutes)..."
LOG_GROUP="/aws/lambda/$LAMBDA_FUNC"
START_TIME=$(($(date +%s) - 600))000

ERRORS=$(aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --start-time "$START_TIME" \
  --region us-east-1 \
  --filter-pattern "ERROR" \
  --max-items 5 \
  --query 'events[*].message' \
  --output text 2>/dev/null || echo "")

if [ -n "$ERRORS" ]; then
  echo "   ⚠️  Recent errors found:"
  echo "$ERRORS" | head -3 | sed 's/^/      /'
else
  echo "   ✅ No recent errors in Lambda logs"
fi

# Step 6: Check for $connect events
echo ""
echo "6️⃣  Checking for WebSocket $connect events..."
CONNECT_EVENTS=$(aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --start-time "$START_TIME" \
  --region us-east-1 \
  --filter-pattern "Connection: type=notification" \
  --max-items 3 \
  --query 'events[*].message' \
  --output text 2>/dev/null || echo "")

if [ -n "$CONNECT_EVENTS" ]; then
  echo "   ✅ Found notification connection attempts:"
  echo "$CONNECT_EVENTS" | head -2 | sed 's/^/      /'
else
  echo "   ⚠️  No notification connection attempts found in last 10 minutes"
  echo "      (This could mean frontend is not connecting or connections are failing silently)"
fi

# Step 7: Check Amplify env vars
echo ""
echo "7️⃣  Checking Amplify Environment Variables..."
AMPLIFY_APP_ID="d26vv4xxnh3x3s"
AMPLIFY_BRANCH="main"

WS_ENDPOINT_AMPLIFY=$(aws amplify get-branch \
  --app-id "$AMPLIFY_APP_ID" \
  --branch-name "$AMPLIFY_BRANCH" \
  --region us-east-1 \
  --query 'branch.environmentVariables.WS_API_ENDPOINT_PRODUCTION' \
  --output text 2>/dev/null || echo "")

if [ -n "$WS_ENDPOINT_AMPLIFY" ] && [ "$WS_ENDPOINT_AMPLIFY" != "None" ]; then
  echo "   ✅ WS_API_ENDPOINT_PRODUCTION: $WS_ENDPOINT_AMPLIFY"
else
  echo "   ❌ WS_API_ENDPOINT_PRODUCTION is NOT SET in Amplify"
  echo ""
  echo "   🔧 FIX: Run Terraform apply to update Amplify:"
  echo "      terraform apply -var-file=terraform.tfvars -var='db_master_password=YOUR_PASSWORD' -auto-approve"
fi

echo ""
echo "=========================================="
echo "📋 Summary & Next Steps"
echo "=========================================="
echo ""
echo "If WebSocket env vars are missing from ECS:"
echo "  1. Run: terraform apply -var-file=terraform.tfvars -var='db_master_password=YOUR_PASSWORD' -auto-approve"
echo "  2. Wait for ECS service to deploy new tasks (check ECS console)"
echo "  3. Test WebSocket connection in browser"
echo ""
echo "If frontend shows 'WebSocket is NOT connected':"
echo "  1. Check browser console for WebSocket connection errors"
echo "  2. Verify WS_API_ENDPOINT_PRODUCTION is set in Amplify (check above)"
echo "  3. Check Lambda CloudWatch logs for $connect event handling"
echo "  4. Verify backend /api/notifications/ws/connect endpoint is working"
echo ""
echo "To check Lambda logs manually:"
echo "  aws logs tail /aws/lambda/$LAMBDA_FUNC --follow --region us-east-1"
echo ""
