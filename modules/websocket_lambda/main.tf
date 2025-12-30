# WebSocket Lambda Proxy Module
# This module creates a Lambda function that proxies WebSocket API Gateway events to the FastAPI backend
# Implements "create if not exists" pattern for resilience

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

locals {
  dynamodb_table_name = var.connections_table_name
  lambda_role_name    = "${var.name}-websocket-lambda-role"
  lambda_function_name = "${var.name}-websocket-proxy"
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ============================================================================
# CHECK IF RESOURCES EXIST (for resilience)
# ============================================================================

# Check if DynamoDB table exists
data "external" "check_dynamodb_table" {
  count = var.create_if_not_exists ? 1 : 0
  
  program = ["bash", "-c", <<-EOT
    if aws dynamodb describe-table --table-name "${local.dynamodb_table_name}" --region "${var.aws_region}" >/dev/null 2>&1; then
      TABLE_ARN=$(aws dynamodb describe-table --table-name "${local.dynamodb_table_name}" --region "${var.aws_region}" --query 'Table.TableArn' --output text 2>/dev/null)
      echo "{\"exists\": \"true\", \"table_arn\": \"$TABLE_ARN\"}"
    else
      echo "{\"exists\": \"false\", \"table_arn\": \"\"}"
    fi
  EOT
  ]
}

# Check if IAM role exists
data "external" "check_iam_role" {
  count = var.create_if_not_exists ? 1 : 0
  
  program = ["bash", "-c", <<-EOT
    if aws iam get-role --role-name "${local.lambda_role_name}" >/dev/null 2>&1; then
      ROLE_ARN=$(aws iam get-role --role-name "${local.lambda_role_name}" --query 'Role.Arn' --output text 2>/dev/null)
      echo "{\"exists\": \"true\", \"role_arn\": \"$ROLE_ARN\"}"
    else
      echo "{\"exists\": \"false\", \"role_arn\": \"\"}"
    fi
  EOT
  ]
}

# Check if Lambda function exists
data "external" "check_lambda_function" {
  count = var.create_if_not_exists ? 1 : 0
  
  program = ["bash", "-c", <<-EOT
    if aws lambda get-function --function-name "${local.lambda_function_name}" --region "${var.aws_region}" >/dev/null 2>&1; then
      FUNC_ARN=$(aws lambda get-function --function-name "${local.lambda_function_name}" --region "${var.aws_region}" --query 'Configuration.FunctionArn' --output text 2>/dev/null)
      echo "{\"exists\": \"true\", \"function_arn\": \"$FUNC_ARN\"}"
    else
      echo "{\"exists\": \"false\", \"function_arn\": \"\"}"
    fi
  EOT
  ]
}

# Determine what to create
locals {
  dynamodb_exists = var.create_if_not_exists ? (
    try(data.external.check_dynamodb_table[0].result.exists, "false") == "true"
  ) : false
  
  existing_table_arn = var.create_if_not_exists ? (
    try(data.external.check_dynamodb_table[0].result.table_arn, "")
  ) : ""
  
  iam_role_exists = var.create_if_not_exists ? (
    try(data.external.check_iam_role[0].result.exists, "false") == "true"
  ) : false
  
  existing_role_arn = var.create_if_not_exists ? (
    try(data.external.check_iam_role[0].result.role_arn, "")
  ) : ""
  
  lambda_exists = var.create_if_not_exists ? (
    try(data.external.check_lambda_function[0].result.exists, "false") == "true"
  ) : false
  
  # When create_if_not_exists=true and resource exists, we should manage it (not create new, not delete)
  # When create_if_not_exists=false, always create if not in state
  should_create_dynamodb = var.create_if_not_exists ? !local.dynamodb_exists : true
  should_create_iam_role = var.create_if_not_exists ? !local.iam_role_exists : true
  should_create_lambda   = var.create_if_not_exists ? !local.lambda_exists : true

  dynamodb_dep      = local.should_create_dynamodb ? [aws_dynamodb_table.websocket_connections] : []
}

# ============================================================================
# DYNAMODB TABLE
# ============================================================================

resource "aws_dynamodb_table" "websocket_connections" {
  count          = local.should_create_dynamodb ? 1 : 0
  name           = local.dynamodb_table_name
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

  ttl {
    enabled        = true
    attribute_name = "ttl"
  }

  tags = merge(var.tags, { Name = local.dynamodb_table_name })
}

# Get existing DynamoDB table if we didn't create one
data "aws_dynamodb_table" "existing" {
  count = local.dynamodb_exists ? 1 : 0
  name  = local.dynamodb_table_name
}

# Effective values
locals {
  effective_table_arn = local.should_create_dynamodb ? (
    length(aws_dynamodb_table.websocket_connections) > 0 ? aws_dynamodb_table.websocket_connections[0].arn : ""
  ) : (
    length(data.aws_dynamodb_table.existing) > 0 ? data.aws_dynamodb_table.existing[0].arn : local.existing_table_arn
  )
  
  effective_table_name = local.dynamodb_table_name
}

# ============================================================================
# IAM ROLE FOR LAMBDA
# ============================================================================

resource "aws_iam_role" "lambda_role" {
  # Always create the role resource - if it exists, Terraform will manage it
  # The create_if_not_exists logic is only for checking, not for skipping creation
  count = 1
  name  = local.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags

  lifecycle {
    # If role exists, import it instead of erroring
    # Terraform will handle the import automatically if the role already exists
  }
}

# Get existing IAM role if we didn't create one
data "aws_iam_role" "existing" {
  count = local.iam_role_exists ? 1 : 0
  name  = local.lambda_role_name
}

locals {
  # Always use the managed role resource
  effective_role_arn = length(aws_iam_role.lambda_role) > 0 ? aws_iam_role.lambda_role[0].arn : ""
  effective_role_id = length(aws_iam_role.lambda_role) > 0 ? aws_iam_role.lambda_role[0].id : local.lambda_role_name
  effective_role_name = local.lambda_role_name
}

# IAM policies - always manage them
resource "aws_iam_role_policy" "lambda_dynamodb" {
  count = 1
  name  = "${var.name}-lambda-dynamodb-policy"
  role  = local.effective_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
        Effect = "Allow"
        Action = [
        "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query",
        "dynamodb:DeleteItem", "dynamodb:Scan", "dynamodb:DescribeTable"
      ]
      Resource = [local.effective_table_arn, "${local.effective_table_arn}/index/*"]
    }]
  })
}

resource "aws_iam_role_policy" "lambda_apigw" {
  count = 1
  name  = "${var.name}-lambda-apigw-policy"
  role  = local.effective_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["execute-api:ManageConnections"]
        Resource = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.api_gateway_id}/*/*/@connections/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count      = 1
  role       = local.effective_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  
  # Wait for role to be fully created and propagated (IAM eventual consistency)
  depends_on = [
    aws_iam_role.lambda_role
  ]
}

# ============================================================================
# LAMBDA FUNCTION
# ============================================================================

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = var.lambda_source_file
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "websocket_proxy" {
  count            = local.should_create_lambda ? 1 : 0
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role             = local.effective_role_arn
  handler          = "websocket_proxy.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = merge({
      BACKEND_URL          = var.backend_url
      CONNECTIONS_TABLE    = local.effective_table_name
        API_GATEWAY_ENDPOINT = var.api_gateway_endpoint
    }, var.additional_environment_variables)
  }

  tags = var.tags

  depends_on = [
    aws_iam_role.lambda_role,
    aws_iam_role_policy.lambda_dynamodb,
    aws_iam_role_policy.lambda_apigw,
    aws_iam_role_policy_attachment.lambda_basic,
    aws_dynamodb_table.websocket_connections
  ]
}

# Lambda permission (only if we created the function)
resource "aws_lambda_permission" "apigw_invoke" {
  count         = local.should_create_lambda ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = local.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.api_gateway_id}/*/*"
  
  depends_on = [aws_lambda_function.websocket_proxy]
}

# ============================================================================
# OUTPUT LOCALS
# ============================================================================

locals {
  effective_function_arn = local.should_create_lambda ? (
    length(aws_lambda_function.websocket_proxy) > 0 ? aws_lambda_function.websocket_proxy[0].arn : ""
  ) : (
    try(data.external.check_lambda_function[0].result.function_arn, "")
  )
  
  effective_invoke_arn = local.should_create_lambda ? (
    length(aws_lambda_function.websocket_proxy) > 0 ? aws_lambda_function.websocket_proxy[0].invoke_arn : ""
  ) : (
    "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${try(data.external.check_lambda_function[0].result.function_arn, "")}/invocations"
  )
}
