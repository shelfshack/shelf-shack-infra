output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.opensearch.name
}

output "service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.opensearch.id
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.opensearch.arn
}

output "security_group_id" {
  description = "Security group ID for the OpenSearch container"
  value       = aws_security_group.opensearch.id
}

output "service_endpoint" {
  description = "Internal endpoint for OpenSearch (service discovery name or IP)"
  value       = "${var.name}-opensearch-service"
}

output "opensearch_port" {
  description = "Port number for OpenSearch"
  value       = 9200
}

output "service_discovery_dns_name" {
  description = "DNS name for service discovery (if enabled). Format: opensearch.<namespace>.local"
  value       = var.service_discovery_namespace_id != null ? "opensearch.${data.aws_service_discovery_dns_namespace.existing[0].name}" : null
}
