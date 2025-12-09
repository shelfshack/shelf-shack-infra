output "security_group_id" {
  description = "Security group ID assigned to the bastion host."
  value       = try(aws_security_group.this[0].id, null)
}

output "instance_id" {
  description = "Instance ID of the bastion host."
  value       = try(aws_instance.this[0].id, null)
}
