output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.dashboards.name
}

output "security_group_id" {
  description = "Security group ID for OpenSearch Dashboards"
  value       = aws_security_group.dashboards.id
}


