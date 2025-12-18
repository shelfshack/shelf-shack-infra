# WebSocket Proxy Lambda Function

This Lambda function proxies WebSocket API Gateway events to your FastAPI backend.

## Setup Instructions

### Step 1: Create Lambda Function via AWS Console

1. **Go to AWS Lambda Console**
   - Navigate to: https://console.aws.amazon.com/lambda/
   - Click **"Create function"**

2. **Choose Authoring options**
   - Select **"Author from scratch"**
   - **Function name**: `shelfshack-websocket-proxy`
   - **Runtime**: **Python 3.11** (or 3.12)
   - **Architecture**: **x86_64**
   - Click **"Create function"**

### Step 2: Upload Code

#### Option A: Upload ZIP file (Recommended)

1. **Package the function:**
   ```bash
   cd lambda
   pip install -r requirements.txt -t .
   # Make sure lambda_function.py is included (it's the entry point)
   zip -r websocket_proxy.zip . -x "*.pyc" "__pycache__/*" "*.pyc" ".git/*" "README.md" "deploy.sh"
   ```
   
   **Important**: The handler file must be named `lambda_function.py` (or configure Handler in Lambda settings)

2. **Upload to Lambda:**
   - In Lambda Console → Your function → **Code** tab
   - Click **"Upload from"** → **".zip file"**
   - Select `websocket_proxy.zip`
   - Click **"Save"**

#### Option B: Use inline code editor (Quick test)

1. Copy the contents of `lambda_function.py` (NOT websocket_proxy.py)
2. Paste into Lambda code editor
3. Note: You'll still need to add dependencies (boto3, requests) - boto3 is included, but requests might need to be added via Lambda layers or deployment package

### Step 4: Configure Environment Variables

In Lambda Console → **Configuration** → **Environment variables**:

Add:
- `BACKEND_URL`: `http://44.206.238.155:8000`
- `API_GATEWAY_ENDPOINT`: (Optional - Will be set after creating WebSocket API - format: `https://{api-id}.execute-api.{region}.amazonaws.com/{stage}`)

**Note**: `AWS_REGION` is automatically set by Lambda and cannot be configured as an environment variable. The code will automatically detect the region.

### Step 4: Configure IAM Permissions

Lambda needs permission to use API Gateway Management API:

1. Go to Lambda function → **Configuration** → **Permissions**
2. Click on the **Execution role**
3. Click **"Add permissions"** → **"Create inline policy"**
4. Use JSON:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "execute-api:ManageConnections"
         ],
         "Resource": "arn:aws:execute-api:*:*:*/*/@connections/*"
       }
     ]
   }
   ```
5. Name: `WebSocketAPIPermissions`
6. Click **"Create policy"**

### Step 6: Configure Function Settings

1. **Timeout**: Set to **30 seconds** (Configuration → General configuration → Edit)
2. **Memory**: **256 MB** (minimum, can increase if needed)

### Step 7: Test the Function

1. In Lambda Console → **Test** tab
2. Create a test event:
   ```json
   {
     "requestContext": {
       "routeKey": "$connect",
       "connectionId": "test-connection-123",
       "domainName": "test.execute-api.us-east-1.amazonaws.com",
       "stage": "dev"
     },
     "queryStringParameters": {
       "booking_id": "1",
       "token": "test-token",
       "type": "booking"
     }
   }
   ```
3. Click **"Test"**
4. Verify it returns `{"statusCode": 200}`

## Integration with WebSocket API Gateway

**Important**: The WebSocket endpoint comes from **API Gateway**, not Lambda. Follow these steps:

### Quick Steps:

1. **Create WebSocket API in API Gateway Console** (see `WEBSOCKET_API_SETUP.md` for detailed instructions)
2. **Configure routes** (`$connect`, `$disconnect`, `$default`) → Point to your Lambda function
3. **Deploy the WebSocket API** → This gives you the endpoint URL
4. **Update Lambda environment variable** with the endpoint URL

### Detailed Instructions:

See `WEBSOCKET_API_SETUP.md` for complete step-by-step guide including:
- How to create WebSocket API
- How to configure routes
- How to deploy and get the endpoint
- How to update environment variables

## Backend Endpoint Requirements

Your FastAPI backend needs HTTP endpoints to receive messages from Lambda:

```python
# Example endpoints you might want to add:

@router.post("/api/ws/message")
async def handle_websocket_message(
    data: dict,
    connection_id: str = Header(None, alias="x-connection-id")
):
    """Handle WebSocket message forwarded from Lambda."""
    # Process message
    # Return response that Lambda will forward to client
    return {"response": "processed"}

@router.post("/api/ws/register")
async def register_connection(data: dict):
    """Register WebSocket connection."""
    # Store connection mapping
    return {"success": True}

@router.post("/api/ws/disconnect")
async def disconnect_connection(data: dict):
    """Handle disconnection."""
    # Cleanup
    return {"success": True}
```

**Note**: The current Lambda implementation forwards messages to backend, but your existing WebSocket endpoints won't work directly. You'll need to either:
1. Add HTTP endpoints that Lambda can call
2. Or modify the Lambda to handle the WebSocket protocol differently

## Troubleshooting

### Lambda can't send messages to client
- Check IAM permissions for `execute-api:ManageConnections`
- Verify `API_GATEWAY_ENDPOINT` environment variable is set correctly
- Check that the endpoint URL matches your WebSocket API deployment

### Backend not receiving messages
- Verify `BACKEND_URL` environment variable is correct
- Check security groups allow Lambda to reach your backend
- Verify backend endpoints exist and are accessible

### Connection timeout
- Increase Lambda timeout (Configuration → General configuration)
- Check backend response times

## Monitoring

- **CloudWatch Logs**: Lambda automatically logs to CloudWatch
- **Metrics**: Monitor Lambda invocations, errors, duration
- **API Gateway Logs**: Enable access logging in API Gateway

## Cost

- **Lambda**: First 1M requests/month FREE (free tier)
- **API Gateway WebSocket**: First 1M messages/month FREE
- **Total**: FREE for reasonable development usage
