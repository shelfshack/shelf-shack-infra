variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "connections_table_name" {
  description = "Name of the DynamoDB table for WebSocket connections"
  type        = string
  default     = "websocket-connections"
}

variable "lambda_source_file" {
  description = "Path to the Lambda function source file"
  type        = string
}

variable "lambda_requirements_file" {
  description = "Path to requirements.txt file for Lambda dependencies (optional, will use defaults if not provided)"
  type        = string
  default     = null
}

variable "backend_url" {
  description = "Backend API URL for the FastAPI application"
  type        = string
}

variable "api_gateway_id" {
  description = "API Gateway WebSocket API ID"
  type        = string
}

variable "api_gateway_endpoint" {
  description = "API Gateway WebSocket endpoint URL (optional, will be constructed if not provided)"
  type        = string
  default     = ""
}

variable "additional_environment_variables" {
  description = "Additional environment variables for Lambda function"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}



