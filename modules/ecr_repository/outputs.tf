output "repository_name" {
  description = "Name of the ECR repository."
  value       = local.repository_name
}

output "repository_url" {
  description = "URI of the ECR repository."
  value       = local.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository."
  value       = local.repository_arn
}

output "repository_created" {
  description = "Whether the repository was created by this module (false if it already existed)."
  value       = local.should_create
}
