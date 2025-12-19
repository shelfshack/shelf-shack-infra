# WebSocket API Gateway and Lambda Proxy Setup

This document describes the WebSocket infrastructure setup for chat functionality in AWS Amplify deployments.

## Overview

The WebSocket infrastructure consists of:
1. **API Gateway WebSocket API** - Handles WebSocket connections
2. **Lambda Function** - Proxies WebSocket events to the FastAPI backend
3. **DynamoDB Table** - Tracks active WebSocket connections for broadcasting

## Architecture

```
Client (Browser)
    ↓
API Gateway WebSocket API
    ↓
Lambda Function (websocket_proxy.py)
    ↓
FastAPI Backend (HTTP endpoints)
    ↓
Database (PostgreSQL)
```

## Components

### 1. DynamoDB Table (`websocket-connections`)

**Schema:**
- **Partition Key**: `booking_id` (String)
- **Sort Key**: `connection_id` (String)
- **Attributes**:
  - `user_id` (String, optional)
  - `connection_type` (String) - "chat", "booking", "notification", "feed"
  - `created_at` (Number) - Unix timestamp
  - `ttl` (Number) - TTL for auto-cleanup (24 hours)

**Created by**: `modules/websocket_lambda/main.tf`

### 2. Lambda Function

**File**: `lambda/websocket_proxy.py` (in backend repo)

**Environment Variables**:
- `BACKEND_URL` - FastAPI backend URL
- `CONNECTIONS_TABLE` - DynamoDB table name
- `API_GATEWAY_ENDPOINT` - API Gateway Management API endpoint

**IAM Permissions**:
- `dynamodb:PutItem`, `GetItem`, `Query`, `DeleteItem`, `Scan`
- `execute-api:ManageConnections`
- CloudWatch Logs (basic execution role)

### 3. API Gateway WebSocket API

**Routes**:
- `$connect` - Connection initialization
- `$disconnect` - Connection cleanup
- `$default` - Message handling

**Stage**: `development` (configurable via `websocket_stage_name` variable)

## Backend HTTP Endpoints

The backend provides HTTP endpoints that Lambda calls:

### POST `/api/chat/ws/{booking_id}/connect`
- Called during `$connect` event
- Authenticates user via token
- Returns initial chat history
- Returns read receipt updates if any

**Request Body**:
```json
{
  "connection_id": "connection-id",
  "token": "jwt-token"
}
```

**Response**:
```json
{
  "initial": {
    "type": "history",
    "thread": {...},
    "messages": [...]
  },
  "receipt": {...}  // Optional
}
```

### POST `/api/chat/ws/{booking_id}/message`
- Called during `$default` event (when client sends message)
- Processes messages and reactions
- Returns broadcast payload

**Request Body**:
```json
{
  "connection_id": "connection-id",
  "message": {
    "body": "Hello"  // or {"type": "reaction", "emoji": "❤️", "message_id": 123}
  },
  "token": "jwt-token"
}
```

**Response**:
```json
{
  "type": "message",
  "message": {...},
  "thread": {...},
  "broadcast": true  // Signal to Lambda to broadcast to all connections
}
```

## Deployment

### Prerequisites

**Option 1: Let Terraform manage Lambda (Recommended)**
- Backend repo must be accessible from infra repo (same parent directory or adjust path)
- Terraform will automatically package and upload the Lambda function
- Lambda source file path must be correct (default: `../../shelf-shack-backend/lambda/websocket_proxy.py`)

**Option 2: Use existing Lambda function**
- If you've already uploaded the Lambda function manually, you can reference it by ARN
- Skip the Lambda creation in Terraform and use `data "aws_lambda_function"` instead
- See "Using Existing Lambda Function" section below

### Terraform Variables

In `envs/dev/terraform.tfvars` (or via environment):

```hcl
websocket_stage_name = "development"
websocket_lambda_source_file = "../../../shelf-shack-backend/lambda/websocket_proxy.py"
websocket_backend_url = "https://api.yourdomain.com"  # Optional, defaults to ALB URL
```

### Apply Infrastructure

```bash
cd envs/dev
terraform init
terraform plan
terraform apply
```

### Outputs

After deployment, you'll get:

- `websocket_api_endpoint` - WebSocket URL (e.g., `wss://abc123.execute-api.us-east-1.amazonaws.com/development`)
- `websocket_api_id` - API Gateway ID
- `websocket_lambda_function_arn` - Lambda function ARN
- `websocket_connections_table_name` - DynamoDB table name

## Frontend Usage

Connect to WebSocket:

```javascript
const ws = new WebSocket(
  `wss://${apiGatewayId}.execute-api.${region}.amazonaws.com/${stage}?type=chat&booking_id=1&token=${token}`
);

ws.onopen = () => {
  console.log('Connected');
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'history') {
    // Load chat history
  } else if (data.type === 'message') {
    // New message received
  }
};

// Send message
ws.send(JSON.stringify({ body: 'Hello!' }));

// Send reaction
ws.send(JSON.stringify({ type: 'reaction', emoji: '❤️', message_id: 123 }));
```

## Local Development

Locally, the WebSocket endpoint (`/chat/ws/{booking_id}`) works directly without Lambda proxy. The HTTP endpoints are still available but not used locally.

## Troubleshooting

### Lambda can't find source file

**Error**: `Error archiving Lambda function: file not found`

**Solution**: Update `websocket_lambda_source_file` variable to correct path:
- **Absolute path** (recommended if repos are in different locations):
  ```hcl
  websocket_lambda_source_file = "/Users/rohitsoni/Desktop/GitProjects/shelf-shack-backend/lambda/websocket_proxy.py"
  ```
- **Relative path from `envs/dev`** (if repos are siblings):
  ```hcl
  websocket_lambda_source_file = "../../shelf-shack-backend/lambda/websocket_proxy.py"
  ```
- **Verify path exists**:
  ```bash
  ls -la ../../shelf-shack-backend/lambda/websocket_proxy.py  # From envs/dev/
  ```

### DynamoDB access denied

**Error**: `AccessDeniedException` when Lambda tries to access DynamoDB

**Solution**: Ensure Lambda execution role has DynamoDB permissions (should be automatic via module)

### Backend connection failed

**Error**: `Backend request failed` in Lambda logs

**Solution**: 
- Check `BACKEND_URL` environment variable in Lambda
- Verify backend is accessible from Lambda (VPC configuration if needed)
- Check backend logs for errors

### Messages not broadcasting

**Error**: Messages only appear for sender, not other users

**Solution**:
- Check DynamoDB table exists and has connections
- Verify `broadcast: true` in backend response
- Check Lambda logs for broadcast errors
- Ensure all clients are connected to same `booking_id`

## Testing

1. **Connect two clients** to same booking_id:
   ```javascript
   // Client 1
   ws1 = new WebSocket('wss://...?type=chat&booking_id=1&token=token1');
   
   // Client 2
   ws2 = new WebSocket('wss://...?type=chat&booking_id=1&token=token2');
   ```

2. **Send message from Client 1**:
   ```javascript
   ws1.send(JSON.stringify({ body: 'Hello!' }));
   ```

3. **Verify both clients receive** the message

4. **Check DynamoDB** for connection records:
   ```bash
   aws dynamodb scan --table-name shelfshack-dev-websocket-connections
   ```

## Cost Considerations

- **DynamoDB**: Pay-per-request pricing, very low cost for chat connections
- **Lambda**: Pay per invocation (very cheap)
- **API Gateway**: Pay per message (first 1M messages/month free)
- **Data Transfer**: Standard AWS data transfer costs

For typical usage, costs should be minimal (< $10/month for moderate traffic).

