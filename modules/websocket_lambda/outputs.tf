output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = local.effective_function_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = local.lambda_function_name
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function (for API Gateway integration)"
  value       = local.effective_invoke_arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = local.effective_table_name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = local.effective_table_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = local.effective_role_arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = local.effective_role_name
}

# Status outputs
output "dynamodb_created" {
  description = "Whether the DynamoDB table was created by this module"
  value       = local.should_create_dynamodb
}

output "iam_role_created" {
  description = "Whether the IAM role was created by this module"
  value       = local.should_create_iam_role
}

output "lambda_created" {
  description = "Whether the Lambda function was created by this module"
  value       = local.should_create_lambda
}
