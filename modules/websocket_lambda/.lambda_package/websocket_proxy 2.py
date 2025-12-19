"""
Lambda function to proxy WebSocket API Gateway events to FastAPI backend.

This Lambda function handles WebSocket connections through API Gateway and
forwards events to your FastAPI backend, then sends responses back via
API Gateway Management API.
"""
import json
import os
import boto3
import requests
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configuration from environment variables
BACKEND_URL = os.environ.get('BACKEND_URL', 'http://44.206.238.155:8000')

# Get AWS region from boto3 session (AWS_REGION is reserved and auto-set by Lambda)
try:
    AWS_REGION = boto3.Session().region_name or 'us-east-1'
except Exception:
    AWS_REGION = 'us-east-1'

# API Gateway Management API client for sending messages back to clients
# Will be initialized with endpoint URL when API Gateway endpoint is available
apigw_management = None


def lambda_handler(event, context):
    """
    Handle WebSocket API Gateway events.
    
    Events:
    - $connect: Client connects
    - $disconnect: Client disconnects
    - $default: Messages from client
    """
    route_key = event.get('requestContext', {}).get('routeKey')
    connection_id = event.get('requestContext', {}).get('connectionId')
    domain_name = event.get('requestContext', {}).get('domainName')
    stage = event.get('requestContext', {}).get('stage')
    
    # Initialize API Gateway Management API client
    global apigw_management
    
    # Use endpoint from environment variable if set, otherwise construct from event
    api_endpoint = os.environ.get('API_GATEWAY_ENDPOINT')
    if not api_endpoint and domain_name and stage:
        api_endpoint = f"https://{domain_name}/{stage}"
    
    if api_endpoint and (apigw_management is None or apigw_management._client_config.endpoint_url != api_endpoint):
        apigw_management = boto3.client(
            'apigatewaymanagementapi',
            endpoint_url=api_endpoint,
            region_name=AWS_REGION
        )
    
    logger.info(f"Route: {route_key}, Connection ID: {connection_id}")
    
    try:
        if route_key == '$connect':
            return handle_connect(event, connection_id)
        elif route_key == '$disconnect':
            return handle_disconnect(event, connection_id)
        elif route_key == '$default':
            return handle_message(event, connection_id)
        else:
            # Custom route keys (if you add any)
            return handle_message(event, connection_id)
    except Exception as e:
        logger.error(f"Error handling {route_key}: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def handle_connect(event, connection_id):
    """
    Handle WebSocket connection.
    Notify backend about the connection and validate authentication.
    """
    # Extract query parameters
    query_params = event.get('queryStringParameters') or {}
    booking_id = query_params.get('booking_id')
    token = query_params.get('token')
    connection_type = query_params.get('type', 'booking')  # booking, chat, notification, feed
    
    logger.info(f"Connection: type={connection_type}, booking_id={booking_id}, connection_id={connection_id}")
    
    # Validate required parameters
    if connection_type in ['booking', 'chat'] and not booking_id:
        logger.warning(f"Missing booking_id for {connection_type} connection")
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'booking_id required for booking/chat connections'})
        }
    
    if not token:
        logger.warning("Missing token for connection")
        return {
            'statusCode': 401,
            'body': json.dumps({'error': 'token required'})
        }
    
    # Notify backend about the connection
    # You can create an HTTP endpoint in your backend to handle this
    # For now, we'll just accept the connection
    # In production, you might want to:
    # 1. Validate token with backend
    # 2. Store connection mapping (connection_id -> user_id, booking_id)
    # 3. Initialize backend state
    
    try:
        # Optionally call backend to register connection
        # backend_response = requests.post(
        #     f"{BACKEND_URL}/api/ws/register",
        #     json={
        #         'connection_id': connection_id,
        #         'type': connection_type,
        #         'booking_id': booking_id,
        #         'token': token
        #     },
        #     timeout=2
        # )
        pass
    except Exception as e:
        logger.warning(f"Failed to notify backend of connection: {e}")
        # Still accept connection - backend will handle it when messages arrive
    
    # Accept the connection
    return {
        'statusCode': 200
    }


def handle_disconnect(event, connection_id):
    """
    Handle WebSocket disconnection.
    Notify backend to clean up connection state.
    """
    logger.info(f"Disconnection: connection_id={connection_id}")
    
    try:
        # Optionally call backend to cleanup
        # backend_response = requests.post(
        #     f"{BACKEND_URL}/api/ws/disconnect",
        #     json={'connection_id': connection_id},
        #     timeout=2
        # )
        pass
    except Exception as e:
        logger.warning(f"Failed to notify backend of disconnection: {e}")
    
    return {
        'statusCode': 200
    }


def handle_message(event, connection_id):
    """
    Handle incoming WebSocket message from client.
    Forward to backend and send response back via API Gateway.
    """
    try:
        # Extract message body
        body = event.get('body')
        if body:
            try:
                message_data = json.loads(body)
            except json.JSONDecodeError:
                message_data = {'text': body}
        else:
            message_data = {}
        
        # Get connection metadata from query params (stored during $connect)
        # In production, you'd store this in DynamoDB or similar
        query_params = event.get('queryStringParameters') or {}
        booking_id = query_params.get('booking_id')
        token = query_params.get('token')
        connection_type = query_params.get('type', 'booking')
        
        logger.info(f"Message: type={connection_type}, booking_id={booking_id}, data={message_data}")
        
        # Forward message to appropriate backend endpoint
        backend_response = None
        
        if connection_type == 'booking':
            # Forward to booking status endpoint
            backend_response = forward_to_backend(
                f"{BACKEND_URL}/api/ws/bookings/{booking_id}/message",
                {
                    'connection_id': connection_id,
                    'message': message_data,
                    'token': token
                }
            )
        elif connection_type == 'chat':
            # Forward to chat endpoint
            backend_response = forward_to_backend(
                f"{BACKEND_URL}/api/ws/{booking_id}/message",
                {
                    'connection_id': connection_id,
                    'message': message_data,
                    'token': token
                }
            )
        elif connection_type == 'notification':
            # Forward to notification endpoint
            backend_response = forward_to_backend(
                f"{BACKEND_URL}/api/ws/message",
                {
                    'connection_id': connection_id,
                    'message': message_data,
                    'token': token
                }
            )
        elif connection_type == 'feed':
            # Forward to feed endpoint
            backend_response = forward_to_backend(
                f"{BACKEND_URL}/api/ws/items-feed/message",
                {
                    'connection_id': connection_id,
                    'message': message_data
                }
            )
        
        # Send response back to client via API Gateway
        if backend_response and backend_response.get('response'):
            send_to_client(connection_id, backend_response['response'])
        
        return {
            'statusCode': 200
        }
        
    except Exception as e:
        logger.error(f"Error handling message: {e}", exc_info=True)
        send_to_client(connection_id, {'error': str(e)})
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def forward_to_backend(url, data):
    """
    Forward message to backend HTTP endpoint.
    """
    try:
        response = requests.post(
            url,
            json=data,
            headers={'Content-Type': 'application/json'},
            timeout=5
        )
        response.raise_for_status()
        return {'success': True, 'response': response.json() if response.content else {}}
    except requests.exceptions.RequestException as e:
        logger.error(f"Backend request failed: {e}")
        return {'success': False, 'error': str(e)}


def send_to_client(connection_id, data):
    """
    Send message to client via API Gateway Management API.
    """
    try:
        apigw_management.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(data).encode('utf-8')
        )
        logger.info(f"Sent message to connection {connection_id}")
    except apigw_management.exceptions.GoneException:
        logger.warning(f"Connection {connection_id} is gone")
    except Exception as e:
        logger.error(f"Failed to send message to connection {connection_id}: {e}")


# Helper function to broadcast messages (can be called from backend)
def broadcast_message(connection_ids, data):
    """
    Broadcast message to multiple connections.
    Can be called from your backend via boto3 if needed.
    """
    for connection_id in connection_ids:
        try:
            send_to_client(connection_id, data)
        except Exception as e:
            logger.error(f"Failed to broadcast to {connection_id}: {e}")

