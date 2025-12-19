# Complete WebSocket API Gateway Setup Guide

## Overview

The WebSocket endpoint (`wss://abc123.execute-api.us-east-1.amazonaws.com/dev`) comes from **API Gateway WebSocket API**, not from Lambda. Here's how to create it:

## Step-by-Step Instructions

### Step 1: Create WebSocket API in API Gateway

1. **Go to AWS API Gateway Console**
   - Navigate to: https://console.aws.amazon.com/apigateway/
   - Make sure you're in the correct region (e.g., `us-east-1`)

2. **Create API**
   - Click **"Create API"** button
   - Under **"WebSocket API"** card, click **"Build"**

3. **Configure API**
   - **API name**: `shelfshack-websocket-api` (or your preferred name)
   - **Route selection expression**: `$default` (this routes all messages to the default route)
   - **Description**: "WebSocket API for ShelfShack real-time features"
   - Click **"Create"**

4. **Note your API ID** - You'll see it in the URL or API overview (e.g., `abc123def4`)

### Step 2: Configure Routes

You need to configure three routes: `$connect`, `$disconnect`, and `$default`.

#### Configure $connect Route

1. In your WebSocket API, click **"Routes"** in the left sidebar
2. Click **"Create"** button
3. **Route key**: Enter `$connect` (exactly as shown)
4. Click **"Next"**

5. **Configure Integration:**
   - **Integration type**: Select **"AWS Service"**
   - **AWS Service**: Select **"Lambda function"**
   - **Lambda function**: Select your Lambda function name (e.g., `shelfshack-websocket-proxy`)
   - **Use Lambda Proxy integration**: ✅ **Enable this** (check the box)
   - Click **"Create"**

6. **If prompted to add Lambda permissions**: Click **"OK"** or **"Add Permission"** (API Gateway needs permission to invoke Lambda)

#### Configure $disconnect Route

1. Click **"Create"** again
2. **Route key**: Enter `$disconnect`
3. Click **"Next"**
4. **Integration type**: **"AWS Service"** → **"Lambda function"**
5. Select the **same Lambda function**
6. ✅ **Enable Lambda Proxy integration**
7. Click **"Create"**

#### Configure $default Route

1. Click **"Create"** again
2. **Route key**: Enter `$default` (this catches all messages)
3. Click **"Next"**
4. **Integration type**: **"AWS Service"** → **"Lambda function"**
5. Select the **same Lambda function**
6. ✅ **Enable Lambda Proxy integration**
7. Click **"Create"**

### Step 3: Deploy the WebSocket API

**This is where you get the endpoint!**

1. In your WebSocket API, click **"Deploy API"** button (top right, or in the left sidebar under "Deployments")

2. **Create deployment:**
   - **Deployment stage**: Select **"Create new stage"** or choose existing stage like `dev` or `development`
   - **Stage name**: Enter `dev` (or `development`, `prod`, etc.)
   - **Stage description**: "Development stage" (optional)
   - Click **"Deploy"**

3. **Get your WebSocket endpoint:**
   - After deployment, you'll see the **Invoke URL** displayed
   - Format: `wss://{api-id}.execute-api.{region}.amazonaws.com/{stage}`
   - Example: `wss://abc123def4.execute-api.us-east-1.amazonaws.com/dev`
   - **Copy this URL** - this is your WebSocket endpoint!

### Step 4: Update Lambda Environment Variable

1. Go back to **Lambda Console** → Your function
2. **Configuration** → **Environment variables**
3. Add or update:
   - `API_GATEWAY_ENDPOINT`: `https://abc123def4.execute-api.us-east-1.amazonaws.com/dev` (use `https://` not `wss://`)

### Step 5: Test the Connection

You can test the WebSocket connection from your browser console or a WebSocket client:

```javascript
const ws = new WebSocket('wss://abc123def4.execute-api.us-east-1.amazonaws.com/dev?booking_id=1&token=your-token&type=booking');

ws.onopen = () => console.log('✅ Connected!');
ws.onmessage = (event) => console.log('📨 Message:', event.data);
ws.onerror = (error) => console.error('❌ Error:', error);
ws.onclose = () => console.log('🔌 Disconnected');
```

### Step 6: Update Frontend Code

Update your frontend to use the new WebSocket endpoint:

```javascript
// In your frontend code (e.g., React component)
const WS_API_ENDPOINT = import.meta.env.VITE_WS_API_ENDPOINT || 'wss://abc123def4.execute-api.us-east-1.amazonaws.com/dev';

// For booking status
const bookingId = 1;
const token = 'your-jwt-token';
const wsUrl = `${WS_API_ENDPOINT}?booking_id=${bookingId}&token=${token}&type=booking`;
const ws = new WebSocket(wsUrl);
```

Add to your Amplify environment variables:
- `VITE_WS_API_ENDPOINT=wss://abc123def4.execute-api.us-east-1.amazonaws.com/dev`

## Visual Guide to Important Buttons

### In API Gateway Console:

```
[Create API] ← Click this first
   ↓
[WebSocket API] [Build] ← Click Build
   ↓
[Routes] → [Create] ← Create routes here
   ↓
[Deploy API] ← This gives you the endpoint!
```

## Common Issues

### Issue 1: "Nothing to deploy" in Lambda
- **This is normal!** Lambda doesn't need deployment - it's already deployed
- The endpoint comes from **API Gateway**, not Lambda
- Go to **API Gateway Console** → Your WebSocket API → **Deploy API**

### Issue 2: Can't find "Deploy API" button
- Make sure you're in the **WebSocket API** (not REST or HTTP API)
- The button is usually in the top right or under "Deployments" in left sidebar

### Issue 3: Routes not working
- Make sure all three routes (`$connect`, `$disconnect`, `$default`) are configured
- Verify Lambda function name matches exactly
- Check Lambda has proper IAM permissions

### Issue 4: Lambda function not appearing in dropdown
- Make sure Lambda function is in the same AWS region as API Gateway
- Refresh the API Gateway page
- Verify Lambda function exists and is active

## Summary Checklist

- [ ] Lambda function created and code uploaded
- [ ] Lambda environment variables configured (`BACKEND_URL`)
- [ ] Lambda IAM permissions configured (execute-api:ManageConnections)
- [ ] WebSocket API created in API Gateway
- [ ] Three routes created: `$connect`, `$disconnect`, `$default`
- [ ] All routes point to your Lambda function
- [ ] Lambda Proxy integration enabled for all routes
- [ ] API deployed to a stage (e.g., `dev`)
- [ ] WebSocket endpoint URL copied
- [ ] Lambda environment variable `API_GATEWAY_ENDPOINT` updated with endpoint
- [ ] Frontend code updated to use new endpoint
- [ ] Tested connection from browser/console

## Quick Reference: Where Things Are

| Component | Location | Action |
|-----------|----------|--------|
| Lambda Function | Lambda Console | Code uploaded here |
| WebSocket API | API Gateway Console | Create API here |
| Routes | API Gateway → Routes | Create $connect, $disconnect, $default |
| Deploy API | API Gateway → Deploy API | Get endpoint here |
| Endpoint URL | After deployment | `wss://{api-id}.execute-api.{region}.amazonaws.com/{stage}` |

## Next Steps After Setup

1. Test WebSocket connection
2. Monitor CloudWatch logs for Lambda and API Gateway
3. Update frontend environment variables in Amplify
4. Deploy frontend changes
5. Test end-to-end WebSocket functionality



