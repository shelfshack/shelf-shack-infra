output "domain_id" {
  description = "Unique identifier for the OpenSearch domain"
  value       = aws_opensearch_domain.this.domain_id
}

output "domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.this.arn
}

output "domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.this.domain_name
}

output "domain_endpoint" {
  description = "Domain-specific endpoint used to submit index, search, and data upload requests"
  value       = aws_opensearch_domain.this.endpoint
}

# Note: kibana_endpoint is deprecated in newer AWS provider versions
# Using dashboard_endpoint output instead which provides the full URL

output "security_group_id" {
  description = "Security group ID for the OpenSearch domain"
  value       = aws_security_group.opensearch.id
}

output "dashboard_endpoint" {
  description = "Dashboard endpoint (OpenSearch Dashboards) with https://"
  # Construct dashboard URL from domain endpoint
  # OpenSearch Dashboards is accessible at the same endpoint with /_dashboards path
  value = "https://${aws_opensearch_domain.this.endpoint}/_dashboards"
}

