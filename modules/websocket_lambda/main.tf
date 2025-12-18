# WebSocket Lambda Proxy Module
# This module creates a Lambda function that proxies WebSocket API Gateway events to the FastAPI backend

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# DynamoDB table for WebSocket connection tracking
resource "aws_dynamodb_table" "websocket_connections" {
  name           = var.connections_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "booking_id"
  range_key      = "connection_id"

  attribute {
    name = "booking_id"
    type = "S"
  }

  attribute {
    name = "connection_id"
    type = "S"
  }

  # TTL for automatic cleanup of stale connections
  ttl {
    enabled        = true
    attribute_name = "ttl"
  }

  tags = merge(
    var.tags,
    {
      Name = var.connections_table_name
    }
  )
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.name}-websocket-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for Lambda to access DynamoDB
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.websocket_connections.arn,
          "${aws_dynamodb_table.websocket_connections.arn}/index/*"
        ]
      }
    ]
  })
}

# IAM policy for Lambda to manage API Gateway connections
resource "aws_iam_role_policy" "lambda_apigw" {
  name = "${var.name}-lambda-apigw-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.api_gateway_id}/*/*/@connections/*"
      }
    ]
  })
}

# IAM policy for Lambda basic execution (CloudWatch logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = var.lambda_source_file
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda function
resource "aws_lambda_function" "websocket_proxy" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.name}-websocket-proxy"
  role            = aws_iam_role.lambda_role.arn
  handler         = "websocket_proxy.lambda_handler"
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 256

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = merge(
      {
        BACKEND_URL        = var.backend_url
        CONNECTIONS_TABLE  = aws_dynamodb_table.websocket_connections.name
        API_GATEWAY_ENDPOINT = var.api_gateway_endpoint
      },
      var.additional_environment_variables
    )
  }

  tags = var.tags
}

# Lambda permission for API Gateway to invoke
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.api_gateway_id}/*/*"
}

