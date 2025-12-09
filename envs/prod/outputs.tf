output "repository_url" {
  description = "ECR repository URL hosting the application image."
  value       = module.ecr.repository_url
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs_service.cluster_name
}

output "service_name" {
  description = "ECS service name."
  value       = module.ecs_service.service_name
}

output "load_balancer_dns" {
  description = "DNS of the public Application Load Balancer."
  value       = module.ecs_service.load_balancer_dns
}

output "rds_endpoint" {
  description = "PostgreSQL endpoint."
  value       = module.rds.endpoint
}

output "bastion_instance_id" {
  description = "Instance ID of the bastion host (if enabled)."
  value       = module.bastion.instance_id
}

# AWS OpenSearch Service outputs (temporarily disabled)
# output "opensearch_domain_endpoint" {
#   description = "OpenSearch domain endpoint (for application connections)"
#   value       = module.opensearch.domain_endpoint
# }
#
# output "opensearch_dashboard_endpoint" {
#   description = "OpenSearch Dashboards endpoint (for browser access)"
#   value       = module.opensearch.dashboard_endpoint
# }
#
# output "opensearch_domain_arn" {
#   description = "ARN of the OpenSearch domain"
#   value       = module.opensearch.domain_arn
# }

# Containerized OpenSearch outputs (DISABLED)
# output "opensearch_container_service_name" {
#   description = "Name of the ECS service running OpenSearch container"
#   value       = module.opensearch_container.service_name
# }
#
# output "opensearch_container_port" {
#   description = "Port number for OpenSearch container (9200)"
#   value       = module.opensearch_container.opensearch_port
# }
#
# output "opensearch_container_security_group_id" {
#   description = "Security group ID for OpenSearch container"
#   value       = module.opensearch_container.security_group_id
# }
#
# output "opensearch_nlb_dns_name" {
#   description = "DNS name of the internal NLB for OpenSearch"
#   value       = module.opensearch_nlb.nlb_dns_name
# }
#
# output "opensearch_dashboards_service_name" {
#   description = "Name of the ECS service running OpenSearch Dashboards"
#   value       = module.opensearch_dashboards.service_name
# }

# Domain endpoints
output "api_endpoint" {
  description = "API endpoint URL"
  value       = try(var.domain_name != null && var.enable_load_balancer ? "https://${var.api_subdomain}.${var.domain_name}" : null, null)
}

# OpenSearch endpoints (DISABLED)
# output "opensearch_endpoint" {
#   description = "OpenSearch endpoint URL (internal, VPC-only). Use NLB DNS name for backend configuration."
#   value       = module.opensearch_nlb.nlb_dns_name
# }
#
# output "opensearch_endpoint_url" {
#   description = "OpenSearch endpoint URL with domain (if configured)"
#   value       = try(var.domain_name != null ? "http://${var.opensearch_subdomain}.${var.domain_name}:9200" : null, null)
# }
#
# output "dashboards_endpoint" {
#   description = "OpenSearch Dashboards endpoint URL"
#   value       = try(var.domain_name != null && var.enable_load_balancer ? "https://${var.dashboards_subdomain}.${var.domain_name}" : null, null)
# }

output "search_backend" {
  description = "Search backend in use (PostgreSQL fallback when OpenSearch is disabled)"
  value       = "PostgreSQL (OpenSearch disabled in AWS)"
}
