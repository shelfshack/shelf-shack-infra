output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "cluster_id" {
  description = "ID of the ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition."
  value       = aws_ecs_task_definition.this.arn
}

output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer."
  value       = var.enable_load_balancer ? aws_lb.this[0].dns_name : null
}

output "target_group_arn" {
  description = "ARN of the target group."
  value       = var.enable_load_balancer ? aws_lb_target_group.this[0].arn : null
}

output "log_group_name" {
  description = "CloudWatch log group used by the service."
  value       = aws_cloudwatch_log_group.this.name
}

output "alb_security_group_id" {
  description = "Security group ID assigned to the ALB."
  value       = var.enable_load_balancer ? aws_security_group.alb[0].id : null
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = var.enable_load_balancer ? aws_lb.this[0].arn : null
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (if HTTPS is enabled)."
  value       = var.enable_load_balancer && var.enable_https ? aws_lb_listener.https[0].arn : null
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener."
  value       = var.enable_load_balancer ? (var.enable_https ? aws_lb_listener.http_redirect[0].arn : aws_lb_listener.http[0].arn) : null
}

output "service_security_group_id" {
  description = "Security group ID assigned to the ECS service."
  value       = aws_security_group.service.id
}

output "route53_record_fqdn" {
  description = "FQDN created in Route53 for the ALB (if configured)."
  value       = try(aws_route53_record.alb_alias[0].fqdn, null)
}

output "task_role_arn" {
  description = "ARN of the ECS task IAM role"
  value       = aws_iam_role.task.arn
}
