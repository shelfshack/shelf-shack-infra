output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.opensearch.id
}

output "private_ip" {
  description = "Private IP address of the OpenSearch EC2 instance"
  value       = aws_instance.opensearch.private_ip
}

output "opensearch_endpoint" {
  description = "OpenSearch HTTP endpoint (http://private_ip:9200)"
  value       = "http://${aws_instance.opensearch.private_ip}:9200"
}

output "opensearch_host" {
  description = "OpenSearch host (private IP only, for use in OPENSEARCH_HOST env var)"
  value       = aws_instance.opensearch.private_ip
}

output "security_group_id" {
  description = "Security group ID of the OpenSearch EC2 instance"
  value       = aws_security_group.opensearch.id
}

