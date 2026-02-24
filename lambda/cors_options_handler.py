"""
Simple Lambda function to handle OPTIONS preflight requests for CORS.
Returns 200 OK with appropriate CORS headers.
This is used by API Gateway HTTP API to handle OPTIONS requests without hitting the backend.
"""

import json


def lambda_handler(event, context):
    """
    Handle OPTIONS preflight requests.
    Returns 200 OK with CORS headers.
    The actual CORS headers are added by API Gateway based on cors_configuration.
    """
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',  # API Gateway will override this with actual origin
            'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization, Accept, Origin, X-Requested-With, X-Requested-Id',
            'Access-Control-Max-Age': '300',
            'Content-Type': 'application/json'
        },
        'body': json.dumps({'message': 'OK'})
    }
