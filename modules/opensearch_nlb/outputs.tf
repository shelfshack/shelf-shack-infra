output "nlb_dns_name" {
  description = "DNS name of the internal NLB"
  value       = aws_lb.opensearch.dns_name
}

output "nlb_arn" {
  description = "ARN of the internal NLB"
  value       = aws_lb.opensearch.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.opensearch.arn
}

output "security_group_id" {
  description = "Security group ID of the NLB"
  value       = aws_security_group.nlb.id
}







