#!/bin/bash
# Deployment script for WebSocket Proxy Lambda function

set -e

FUNCTION_NAME="shelfshack-websocket-proxy"
REGION="us-east-1"

echo "Building deployment package..."

# Create deployment package
cd "$(dirname "$0")"
rm -rf package websocket_proxy.zip
mkdir -p package

# Install dependencies
pip install -r requirements.txt -t package/

# Copy function code (lambda_function.py is the entry point)
cp lambda_function.py package/

# Create ZIP file
cd package
zip -r ../websocket_proxy.zip .
cd ..

echo "Deployment package created: websocket_proxy.zip"
echo ""
echo "To upload to Lambda:"
echo "1. Go to AWS Lambda Console"
echo "2. Select function: $FUNCTION_NAME"
echo "3. Upload websocket_proxy.zip"
echo ""
echo "Or use AWS CLI:"
echo "aws lambda update-function-code --function-name $FUNCTION_NAME --zip-file fileb://websocket_proxy.zip --region $REGION"



