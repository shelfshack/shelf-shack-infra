"""
Lambda function to proxy WebSocket API Gateway events to FastAPI backend.

This Lambda function handles WebSocket connections through API Gateway and
forwards events to your FastAPI backend, then sends responses back via
API Gateway Management API.

⚡ PERFORMANCE OPTIMIZATION (V2):
- Chat $connect NO LONGER loads history (reduces latency from 400-900ms to <50ms)
- Frontend must fetch history via HTTP GET /api/chat/bookings/{booking_id}
- WebSocket is only for real-time updates (NEW_MESSAGE, reaction, etc.)
"""
import json
import os
import boto3
import urllib.request
import urllib.error
import urllib.parse
import logging
import concurrent.futures
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configuration from environment variables
BACKEND_URL = os.environ.get('BACKEND_URL', 'http://44.206.238.155:8000')
CONNECTIONS_TABLE = os.environ.get('CONNECTIONS_TABLE', 'websocket-connections')

# Get AWS region from boto3 session (AWS_REGION is reserved and auto-set by Lambda)
try:
    AWS_REGION = boto3.Session().region_name or 'us-east-1'
except Exception:
    AWS_REGION = 'us-east-1'

# API Gateway Management API client for sending messages back to clients
# Will be initialized with endpoint URL when API Gateway endpoint is available
apigw_management = None

# DynamoDB client for connection tracking
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
connections_table = None


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
    
    # Initialize client - always recreate to ensure correct endpoint
    # (client is lightweight, so this is safe and avoids config access issues)
    if api_endpoint:
        try:
            apigw_management = boto3.client(
                'apigatewaymanagementapi',
                endpoint_url=api_endpoint,
                region_name=AWS_REGION
            )
            logger.info(f"Initialized API Gateway Management API client with endpoint: {api_endpoint}")
        except Exception as e:
            logger.error(f"Failed to initialize API Gateway Management API client: {e}")
            apigw_management = None
    else:
        logger.warning("API Gateway endpoint not available, client not initialized")
        apigw_management = None
    
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
    
    # ⚡ SINGLE WEBSOCKET PER USER: For chat connections, booking_id is optional in URL
    # booking_id will be in message payloads for routing
    # Validate required parameters
    if connection_type == 'booking' and not booking_id:
        logger.warning(f"Missing booking_id for booking connection")
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'booking_id required for booking connections'})
        }
    
    # For chat, booking_id is optional (single WebSocket per user)
    # For booking status, booking_id is required
    
    # Token is optional for feed, but required for booking, chat, and notification
    if connection_type in ['booking', 'chat', 'notification'] and not token:
        logger.warning(f"Missing token for {connection_type} connection")
        return {
            'statusCode': 401,
            'body': json.dumps({'error': 'token required for booking/chat/notification connections'})
        }
    
    # For notification connections, we need user_id from token
    user_id = None
    if connection_type == 'notification' and token:
        try:
            # Validate token and get user_id from backend
            backend_response = forward_to_backend(
                f"{BACKEND_URL}/api/notifications/ws/connect",
                {
                    'connection_id': connection_id,
                    'token': token
                }
            )
            if backend_response and backend_response.get('response'):
                user_id = backend_response['response'].get('user_id')
                logger.info(f"Got user_id {user_id} for notification connection {connection_id}")
        except Exception as e:
            logger.warning(f"Failed to validate token for notification connection: {e}")
            # Still accept connection - user_id will be None
    
    # Store connection in DynamoDB for broadcasting (include token for message routing)
    if connection_type == 'chat':
        if booking_id:
            # Legacy: per-chat connection (still supported)
            try:
                store_connection(connection_id, booking_id, user_id=None, connection_type=connection_type, token=token)
                logger.info(f"Stored chat connection {connection_id} for booking {booking_id}")
            except Exception as e:
                logger.warning(f"Failed to store connection in DynamoDB: {e}")
        else:
            # Single WebSocket per user: Store with user_id pattern
            # Get user_id from backend response (if available) or from token validation
            try:
                # For single user connection, we need to validate token and get user_id
                # This happens in the chat connect handler below
                # We'll store it after we get the user_id from backend
                logger.info(f"Single user chat connection (no booking_id) - will store after auth")
            except Exception as e:
                logger.warning(f"Failed to prepare single user chat connection storage: {e}")
    elif connection_type == 'booking' and booking_id:
        try:
            store_connection(connection_id, booking_id, user_id=None, connection_type=connection_type, token=token)
            logger.info(f"Stored {connection_type} connection {connection_id} for booking {booking_id}")
        except Exception as e:
            logger.warning(f"Failed to store connection in DynamoDB: {e}")
            # Continue anyway - connection can still work without DynamoDB storage
    elif connection_type == 'notification' and user_id:
        # Store notification connection with special booking_id format: "user_{user_id}"
        try:
            store_connection(connection_id, f"user_{user_id}", user_id=user_id, connection_type='notification', token=token)
            logger.info(f"Stored notification connection {connection_id} for user {user_id}")
        except Exception as e:
            logger.warning(f"Failed to store notification connection in DynamoDB: {e}")
            # Continue anyway
    
    # For chat connections, call backend for authentication and connection validation only
    # ⚠️ CRITICAL: NO HISTORY LOADING - Frontend must fetch history via HTTP GET /api/chat/bookings/{booking_id}
    # This reduces $connect latency from 400-900ms to <50ms
    if connection_type == 'chat' and token:
        logger.info(f"Calling backend for chat connect (auth only, no history): booking_id={booking_id or 'NONE (single WS per user)'}, connection_id={connection_id}")
        try:
            # For single WebSocket per user, use generic endpoint (no booking_id)
            # For per-chat connections, use booking-specific endpoint
            if booking_id:
                backend_url = f"{BACKEND_URL}/api/chat/ws/{booking_id}/connect"
                logger.info(f"Backend URL: {backend_url}")
                
                # Call backend for authentication and validation only (fast, no history)
                backend_response = forward_to_backend(
                    backend_url,
                    {
                        'connection_id': connection_id,
                        'token': token
                    }
                )
                logger.info(f"Backend response received: success={backend_response.get('success') if backend_response else False}")
                
                # Backend now returns minimal ACK: {user_id, booking_id, thread_id, status: "connected"}
                # Send ACK to client (optional - connection is already established)
                if backend_response and backend_response.get('success') and backend_response.get('response'):
                    response_data = backend_response['response']
                    logger.info(f"Chat connect ACK: {response_data.get('status')}, user_id={response_data.get('user_id')}")
                    # Optionally send ACK to client (not required, but helpful for debugging)
                    try:
                        send_to_client(connection_id, {
                            'type': 'connected',
                            'status': 'ready',
                            'message': 'WebSocket connected. Fetch chat history via HTTP GET /api/chat/bookings/{booking_id}'
                        })
                    except Exception as send_error:
                        # Connection might be closed - this is OK, frontend will use HTTP
                        logger.warning(f"Failed to send ACK (connection may be closed): {send_error}")
                else:
                    error_msg = backend_response.get('error', 'Unknown error') if backend_response else 'No response'
                    logger.error(f"Backend auth failed: {error_msg}")
            else:
                # Single WebSocket per user - call generic connect endpoint
                backend_url = f"{BACKEND_URL}/api/chat/ws/connect"
                logger.info(f"Backend URL (generic): {backend_url}")
                
                backend_response = forward_to_backend(
                    backend_url,
                    {
                        'connection_id': connection_id,
                        'token': token
                    }
                )
                logger.info(f"Backend response received: success={backend_response.get('success') if backend_response else False}")
                
                # Send ACK to client and store connection with user_id pattern
                if backend_response and backend_response.get('success') and backend_response.get('response'):
                    response_data = backend_response['response']
                    user_id = response_data.get('user_id')
                    logger.info(f"Generic chat connect ACK: {response_data.get('status')}, user_id={user_id}")
                    
                    # Store single user chat connection with user_id pattern
                    if user_id:
                        try:
                            store_connection(connection_id, f"user_{user_id}", user_id=user_id, connection_type='chat', token=token)
                            logger.info(f"Stored single user chat connection {connection_id} for user {user_id}")
                        except Exception as e:
                            logger.warning(f"Failed to store single user chat connection: {e}")
                    
                    try:
                        send_to_client(connection_id, {
                            'type': 'connected',
                            'status': 'ready',
                            'message': 'WebSocket connected. Fetch chat history via HTTP GET /api/chat/bookings/{booking_id}'
                        })
                    except Exception as send_error:
                        logger.warning(f"Failed to send ACK (connection may be closed): {send_error}")
                else:
                    error_msg = backend_response.get('error', 'Unknown error') if backend_response else 'No response'
                    logger.error(f"Backend auth failed: {error_msg}")
            
            # Remove duplicate code below - it's now handled above
            if False:  # This block is now dead code, keeping for reference
                logger.info(f"Backend URL: {backend_url}")
                
                # Call backend for authentication and validation only (fast, no history)
                backend_response = forward_to_backend(
                    backend_url,
                    {
                        'connection_id': connection_id,
                        'token': token
                    }
                )
                logger.info(f"Backend response received: success={backend_response.get('success') if backend_response else False}")
                
                # Backend now returns minimal ACK: {user_id, booking_id, thread_id, status: "connected"}
                # Send ACK to client (optional - connection is already established)
                if backend_response and backend_response.get('success') and backend_response.get('response'):
                    response_data = backend_response['response']
                    logger.info(f"Chat connect ACK: {response_data.get('status')}, user_id={response_data.get('user_id')}")
                    # Optionally send ACK to client (not required, but helpful for debugging)
                    try:
                        send_to_client(connection_id, {
                            'type': 'connected',
                            'status': 'ready',
                            'message': 'WebSocket connected. Fetch chat history via HTTP GET /api/chat/bookings/{booking_id}'
                        })
                    except Exception as send_error:
                        # Connection might be closed - this is OK, frontend will use HTTP
                        logger.warning(f"Failed to send ACK (connection may be closed): {send_error}")
                else:
                    error_msg = backend_response.get('error', 'Unknown error') if backend_response else 'No response'
                    logger.error(f"Backend auth failed: {error_msg}")
        except Exception as e:
            logger.error(f"Failed to authenticate chat connection: {e}", exc_info=True)
            # Still accept connection - client can retry auth if needed
    
    # For booking status connections, call backend to get initial status
    if connection_type == 'booking' and booking_id and token:
        logger.info(f"Calling backend for booking status connect: booking_id={booking_id}, connection_id={connection_id}")
        try:
            backend_url = f"{BACKEND_URL}/api/ws/bookings/{booking_id}/connect"
            logger.info(f"Backend URL: {backend_url}")
            
            backend_response = forward_to_backend(
                backend_url,
                {
                    'connection_id': connection_id,
                    'token': token
                }
            )
            logger.info(f"Backend response received: success={backend_response.get('success') if backend_response else False}")
            
            # Send initial status to client
            if backend_response and backend_response.get('success') and backend_response.get('response'):
                response_data = backend_response['response']
                logger.info(f"Response data keys: {list(response_data.keys())}")
                if response_data.get('initial'):
                    logger.info(f"Sending initial status to connection {connection_id}")
                    try:
                        send_to_client(connection_id, response_data['initial'])
                        logger.info(f"Successfully sent initial status to {connection_id}")
                    except Exception as send_error:
                        logger.error(f"Failed to send initial status: {send_error}")
                else:
                    logger.warning(f"No 'initial' key in response data: {response_data}")
            else:
                error_msg = backend_response.get('error', 'Unknown error') if backend_response else 'No response'
                logger.error(f"Backend call failed or invalid response: {error_msg}")
        except Exception as e:
            logger.error(f"Failed to get initial status from backend: {e}", exc_info=True)
            # Still accept connection - client can request status separately if needed
    
    # For notification connections, call backend to get initial notifications
    if connection_type == 'notification' and user_id and token:
        try:
            backend_response = forward_to_backend(
                f"{BACKEND_URL}/api/notifications/ws/connect",
                {
                    'connection_id': connection_id,
                    'token': token
                }
            )
            
            # Send initial notifications to client
            if backend_response and backend_response.get('response'):
                response_data = backend_response['response']
                if response_data.get('initial'):
                    logger.info(f"Sending initial notifications to connection {connection_id}")
                    try:
                        send_to_client(connection_id, response_data['initial'])
                        logger.info(f"Successfully sent initial notifications to {connection_id}")
                    except Exception as send_error:
                        # Connection might be closed - this is OK, frontend will use HTTP fallback
                        logger.warning(f"Failed to send initial notifications (connection may be closed): {send_error}")
        except Exception as e:
            logger.warning(f"Failed to get initial notifications from backend: {e}")
            # Still accept connection
    
    # Accept the connection
    return {
        'statusCode': 200
    }


def handle_disconnect(event, connection_id):
    """
    Handle WebSocket disconnection.
    Remove connection from DynamoDB.
    """
    logger.info(f"Disconnection: connection_id={connection_id}")
    
    try:
        # Remove connection from DynamoDB
        remove_connection(connection_id, booking_id=None)  # booking_id=None will scan and remove
    except Exception as e:
        logger.warning(f"Failed to remove connection from DynamoDB: {e}")
        # Continue anyway - connection is already closed
    
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
        
        # ⚡ SINGLE WEBSOCKET PER USER: Extract booking_id from message payload
        # For single WebSocket per user, booking_id comes in message payload, not connection metadata
        booking_id_from_payload = message_data.get('booking_id')
        
        # Get connection metadata from DynamoDB (stored during $connect)
        # Query params aren't available in $default route, so we retrieve from DynamoDB
        logger.info(f"Getting connection metadata for connection_id={connection_id}")
        connection_metadata = get_connection_metadata(connection_id)
        if connection_metadata:
            booking_id = connection_metadata.get('booking_id')
            token = connection_metadata.get('token')
            connection_type = connection_metadata.get('connection_type', 'booking')
            logger.info(f"Found connection metadata: type={connection_type}, booking_id={booking_id}, has_token={bool(token)}")
        else:
            # For single WebSocket per user, connection might be stored with user_id pattern
            # Try to extract booking_id from message payload
            if booking_id_from_payload:
                logger.info(f"Connection metadata not found, but booking_id in payload: {booking_id_from_payload}")
                # Try to get token from message (if provided)
                token = message_data.get('token') or token
                connection_type = 'chat'
                booking_id = booking_id_from_payload
            else:
                logger.error(f"Could not retrieve connection metadata from DynamoDB for {connection_id} and no booking_id in payload.")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Connection metadata not found. Please reconnect.'})
                }
        
        # Use booking_id from payload if available (for single WebSocket per user)
        if booking_id_from_payload:
            booking_id = booking_id_from_payload
            logger.info(f"Using booking_id from message payload: {booking_id}")
        
        logger.info(f"Message: type={connection_type}, booking_id={booking_id}, data={message_data}")
        
        # Forward message to appropriate backend endpoint
        backend_response = None
        
        if connection_type == 'booking':
            # Booking status is one-way (backend -> client), so messages from client are not expected
            # But if client sends a message (e.g., ping/keepalive), just acknowledge it
            logger.info(f"Booking status connection received message (likely keepalive): {message_data}")
            # Return acknowledgment - booking status updates come from backend, not client messages
            send_to_client(connection_id, {"type": "ack", "message": "Received"})
            return {
                'statusCode': 200
            }
        elif connection_type == 'chat':
            # Forward to chat HTTP endpoint (matches router prefix /chat)
            # booking_id is required for the endpoint
            if not booking_id:
                logger.error(f"Missing booking_id for chat message")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'booking_id required in message payload'})
                }
            
            backend_response = forward_to_backend(
                f"{BACKEND_URL}/api/chat/ws/{booking_id}/message",
                {
                    'connection_id': connection_id,
                    'message': message_data,
                    'token': token
                }
            )
        elif connection_type == 'notification':
            # Forward to notification endpoint
            backend_response = forward_to_backend(
                f"{BACKEND_URL}/api/notifications/ws/message",
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
        
        # Handle response from backend
        if not backend_response or not backend_response.get('success'):
            error_msg = backend_response.get('error', 'Unknown error') if backend_response else 'No response from backend'
            logger.error(f"Backend request failed: {error_msg}")
            return {
                'statusCode': 502,
                'body': json.dumps({'error': f'Backend request failed: {error_msg}'})
            }
        
        if backend_response.get('response'):
            response_data = backend_response['response']
            logger.info(f"Backend response received: type={response_data.get('type')}, broadcast={response_data.get('broadcast')}")
            
            # If backend indicates this should be broadcast
            if response_data.get('broadcast'):
                # Extract booking_id from response payload (for single WebSocket per user routing)
                response_booking_id = response_data.get('booking_id') or booking_id
                
                if connection_type == 'chat' and response_booking_id:
                    # Broadcast to all connections for this booking_id
                    # For single WebSocket per user, also broadcast to user connections
                    all_connection_ids = get_connection_ids_for_booking(response_booking_id, connection_type='chat')
                    
                    # ⚡ SINGLE WEBSOCKET PER USER: Also get user connections
                    # Get owner_id and renter_id from backend to find user connections
                    try:
                        # Call backend to get booking participants
                        booking_info_response = forward_to_backend(
                            f"{BACKEND_URL}/api/chat/ws/{response_booking_id}/participants",
                            {'token': token} if token else {}
                        )
                        if booking_info_response and booking_info_response.get('success') and booking_info_response.get('response'):
                            participants = booking_info_response['response']
                            owner_id = participants.get('owner_id')
                            renter_id = participants.get('renter_id')
                            
                            # Get connections for owner and renter (single WebSocket per user)
                            if owner_id:
                                owner_connections = get_connection_ids_for_booking(f"user_{owner_id}", connection_type='chat')
                                all_connection_ids.extend(owner_connections)
                                logger.info(f"Found {len(owner_connections)} owner connections for user_{owner_id}")
                            if renter_id:
                                renter_connections = get_connection_ids_for_booking(f"user_{renter_id}", connection_type='chat')
                                all_connection_ids.extend(renter_connections)
                                logger.info(f"Found {len(renter_connections)} renter connections for user_{renter_id}")
                    except Exception as e:
                        logger.warning(f"Failed to get booking participants for broadcast: {e}")
                        # Continue with just booking_id connections
                    
                    # Remove duplicates
                    all_connection_ids = list(set(all_connection_ids))
                    logger.info(f"Broadcasting to {len(all_connection_ids)} total connections for booking {response_booking_id}: {all_connection_ids}")
                    
                    # ⚡ BATCH BROADCAST: Send in chunks of 25 (API Gateway limit) with parallel execution
                    # This improves performance when broadcasting to many connections
                    def send_to_connection(conn_id):
                        try:
                            send_to_client(conn_id, response_data)
                            return {'success': True, 'connection_id': conn_id}
                        except ClientError as e:
                            error_code = e.response.get('Error', {}).get('Code', '')
                            if error_code == 'GoneException':
                                logger.warning(f"Connection {conn_id} is gone - will be cleaned up on $disconnect")
                            else:
                                logger.error(f"Failed to send to connection {conn_id}: {e}")
                            return {'success': False, 'connection_id': conn_id, 'error': str(e)}
                        except Exception as e:
                            if 'GoneException' in str(type(e)) or 'Gone' in str(e):
                                logger.warning(f"Connection {conn_id} is gone - will be cleaned up on $disconnect")
                            else:
                                logger.error(f"Failed to send to connection {conn_id}: {e}")
                            return {'success': False, 'connection_id': conn_id, 'error': str(e)}
                    
                    # Batch connections into chunks of 25
                    chunk_size = 25
                    broadcast_count = 0
                    for i in range(0, len(all_connection_ids), chunk_size):
                        chunk = all_connection_ids[i:i + chunk_size]
                        logger.info(f"Broadcasting to chunk {i//chunk_size + 1}: {len(chunk)} connections")
                        
                        # Use ThreadPoolExecutor for parallel sends within each chunk
                        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
                            futures = [executor.submit(send_to_connection, conn_id) for conn_id in chunk]
                            for future in concurrent.futures.as_completed(futures):
                                result = future.result()
                                if result.get('success'):
                                    broadcast_count += 1
                    
                    logger.info(f"Broadcast complete: sent to {broadcast_count}/{len(all_connection_ids)} connections")
                elif connection_type == 'notification' and response_data.get('user_id'):
                    # Broadcast to all connections for this user_id
                    user_id = response_data['user_id']
                    all_connection_ids = get_connection_ids_for_user(str(user_id), connection_type='notification')
                    logger.info(f"Broadcasting to {len(all_connection_ids)} notification connections for user {user_id}")
                    
                    broadcast_count = 0
                    for conn_id in all_connection_ids:
                        try:
                            send_to_client(conn_id, response_data)
                            broadcast_count += 1
                        except Exception as e:
                            logger.error(f"Failed to send to connection {conn_id}: {e}")
                            # Connection might be dead, remove it
                            remove_connection(conn_id, f"user_{user_id}")
                    
                    logger.info(f"Broadcast complete: sent to {broadcast_count}/{len(all_connection_ids)} notification connections")
                else:
                    # Send response back to sender only
                    send_to_client(connection_id, response_data)
            else:
                # Send response back to sender only
                send_to_client(connection_id, response_data)
        
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
    Uses urllib instead of requests (which isn't available in Lambda by default).
    """
    try:
        # Prepare the request
        json_data = json.dumps(data).encode('utf-8')
        req = urllib.request.Request(
            url,
            data=json_data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        
        # Make the request with timeout (reduced to 3 seconds to prevent connection timeout)
        with urllib.request.urlopen(req, timeout=3) as response:
            response_data = response.read().decode('utf-8')
            status_code = response.getcode()
            
            if status_code >= 200 and status_code < 300:
                try:
                    parsed_response = json.loads(response_data) if response_data else {}
                    return {'success': True, 'response': parsed_response}
                except json.JSONDecodeError:
                    return {'success': True, 'response': {}}
            else:
                logger.error(f"Backend request failed with status {status_code}: {response_data}")
                return {'success': False, 'error': f"HTTP {status_code}"}
                
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8') if hasattr(e, 'read') else str(e)
        logger.error(f"Backend HTTP error: {e.code} - {error_body}")
        return {'success': False, 'error': f"HTTP {e.code}: {error_body}"}
    except urllib.error.URLError as e:
        logger.error(f"Backend URL error: {e}")
        return {'success': False, 'error': str(e)}
    except Exception as e:
        logger.error(f"Backend request failed: {e}")
        return {'success': False, 'error': str(e)}


def send_to_client(connection_id, data):
    """
    Send message to client via API Gateway Management API.
    """
    global apigw_management
    
    if apigw_management is None:
        logger.error("API Gateway Management API client not initialized, cannot send message")
        return
    
    try:
        apigw_management.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(data).encode('utf-8')
        )
        logger.info(f"Sent message to connection {connection_id}")
    except apigw_management.exceptions.GoneException:
        logger.warning(f"Connection {connection_id} is gone - will be cleaned up on $disconnect")
        # Don't remove immediately - let $disconnect handle cleanup to avoid race conditions
        # Messages might still be in flight when connection closes
        raise  # Re-raise so caller knows the send failed
    except Exception as e:
        logger.error(f"Failed to send message to connection {connection_id}: {e}", exc_info=True)


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


# DynamoDB connection tracking functions

def get_connections_table():
    """Get or create DynamoDB table reference."""
    global connections_table
    if connections_table is None:
        try:
            connections_table = dynamodb.Table(CONNECTIONS_TABLE)
            # Test access by describing the table
            connections_table.meta.client.describe_table(TableName=CONNECTIONS_TABLE)
            logger.info(f"Connected to DynamoDB table: {CONNECTIONS_TABLE}")
        except Exception as e:
            logger.warning(f"DynamoDB table {CONNECTIONS_TABLE} not accessible: {e}")
            return None
    return connections_table


def store_connection(connection_id: str, booking_id: str, user_id: str = None, connection_type: str = 'chat', token: str = None):
    """
    Store WebSocket connection in DynamoDB.
    
    Args:
        connection_id: API Gateway connection ID
        booking_id: Booking ID this connection is for (or "user_{user_id}" for notifications)
        user_id: User ID (optional, can be None initially)
        connection_type: Type of connection (chat, booking, notification, feed)
        token: JWT token (optional, stored for message routing)
    """
    table = get_connections_table()
    if not table:
        logger.warning("DynamoDB table not available, skipping connection storage")
        return
    
    try:
        import time
        ttl = int(time.time()) + (24 * 60 * 60)  # 24 hours from now
        
        item = {
            'booking_id': str(booking_id),
            'connection_id': connection_id,
            'connection_type': connection_type,
            'created_at': int(time.time()),
            'ttl': ttl
        }
        
        if user_id:
            item['user_id'] = str(user_id)
        
        # Store token for message routing (will be used to get booking_id/user_id during $default)
        if token:
            item['token'] = token
        
        table.put_item(Item=item)
        logger.info(f"Stored connection: {connection_id} for booking {booking_id}, type {connection_type}")
    except Exception as e:
        logger.error(f"Failed to store connection in DynamoDB: {e}")
        raise


def remove_connection(connection_id: str, booking_id: str = None):
    """
    Remove WebSocket connection from DynamoDB.
    
    Args:
        connection_id: API Gateway connection ID to remove
        booking_id: Booking ID (optional, if None will scan to find it)
    """
    table = get_connections_table()
    if not table:
        logger.warning("DynamoDB table not available, skipping connection removal")
        return
    
    try:
        if booking_id:
            # Direct delete if we know the booking_id
            table.delete_item(
                Key={
                    'booking_id': str(booking_id),
                    'connection_id': connection_id
                }
            )
            logger.info(f"Removed connection: {connection_id} for booking {booking_id}")
        else:
            # Scan to find the connection if booking_id is unknown
            # This is less efficient but needed for disconnect events
            response = table.scan(
                FilterExpression='connection_id = :conn_id',
                ExpressionAttributeValues={
                    ':conn_id': connection_id
                }
            )
            
            for item in response.get('Items', []):
                table.delete_item(
                    Key={
                        'booking_id': item['booking_id'],
                        'connection_id': connection_id
                    }
                )
                logger.info(f"Removed connection: {connection_id} for booking {item.get('booking_id')}")
    except Exception as e:
        logger.error(f"Failed to remove connection from DynamoDB: {e}")


def get_connection_ids_for_booking(booking_id: str, connection_type: str = 'chat'):
    """
    Get all connection IDs for a given booking_id.
    
    Args:
        booking_id: Booking ID to get connections for
        connection_type: Type of connection to filter by (default: 'chat')
    
    Returns:
        List of connection IDs
    """
    table = get_connections_table()
    if not table:
        logger.warning("DynamoDB table not available, returning empty connection list")
        return []
    
    try:
        # Query by booking_id (hash key) and filter by connection_type
        response = table.query(
            KeyConditionExpression='booking_id = :booking_id',
            FilterExpression='connection_type = :conn_type',
            ExpressionAttributeValues={
                ':booking_id': str(booking_id),
                ':conn_type': connection_type
            }
        )
        
        connection_ids = [item['connection_id'] for item in response.get('Items', [])]
        logger.info(f"Found {len(connection_ids)} {connection_type} connections for booking {booking_id}: {connection_ids}")
        return connection_ids
    except Exception as e:
        logger.error(f"Failed to query connections from DynamoDB: {e}", exc_info=True)
        return []


def get_connection_ids_for_user(user_id: str, connection_type: str = 'notification'):
    """
    Get all connection IDs for a given user_id.
    
    Args:
        user_id: User ID to get connections for
        connection_type: Type of connection to filter by (default: 'notification')
    
    Returns:
        List of connection IDs
    """
    table = get_connections_table()
    if not table:
        logger.warning("DynamoDB table not available, returning empty connection list")
        return []
    
    try:
        # Use special booking_id format: "user_{user_id}"
        booking_id = f"user_{user_id}"
        response = table.query(
            KeyConditionExpression='booking_id = :booking_id',
            FilterExpression='connection_type = :conn_type',
            ExpressionAttributeValues={
                ':booking_id': booking_id,
                ':conn_type': connection_type
            }
        )
        
        connection_ids = [item['connection_id'] for item in response.get('Items', [])]
        logger.info(f"Found {len(connection_ids)} connections for user {user_id}")
        return connection_ids
    except Exception as e:
        logger.error(f"Failed to query connections from DynamoDB for user {user_id}: {e}")
        return []


def get_connection_metadata(connection_id: str):
    """
    Get connection metadata (booking_id, token, connection_type) from DynamoDB.
    
    Args:
        connection_id: Connection ID to look up
    
    Returns:
        Dict with booking_id, token, connection_type, user_id (if available), or None if not found
    """
    table = get_connections_table()
    if not table:
        logger.warning("DynamoDB table not available, cannot retrieve connection metadata")
        return None
    
    try:
        # Scan for the connection_id (since it's the range key, we need to scan)
        # Handle pagination to ensure we find the connection even if it's not on the first page
        items = []
        last_evaluated_key = None
        
        while True:
            scan_kwargs = {
                'FilterExpression': 'connection_id = :conn_id',
                'ExpressionAttributeValues': {
                    ':conn_id': connection_id
                }
            }
            
            if last_evaluated_key:
                scan_kwargs['ExclusiveStartKey'] = last_evaluated_key
            
            response = table.scan(**scan_kwargs)
            items.extend(response.get('Items', []))
            
            # Check if there are more pages
            last_evaluated_key = response.get('LastEvaluatedKey')
            
            # If we found the item, break
            if items:
                break
            
            if not last_evaluated_key:
                break
        
        if items:
            item = items[0]
            metadata = {
                'booking_id': item.get('booking_id'),
                'token': item.get('token'),
                'connection_type': item.get('connection_type', 'booking'),
                'user_id': item.get('user_id')
            }
            logger.info(f"Retrieved connection metadata for {connection_id}: type={metadata['connection_type']}, booking_id={metadata['booking_id']}")
            return metadata
        
        logger.warning(f"Connection metadata not found for {connection_id}")
        return None
    except Exception as e:
        logger.error(f"Failed to retrieve connection metadata from DynamoDB: {e}", exc_info=True)
        return None


