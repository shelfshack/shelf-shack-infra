output "endpoint" {
  description = "RDS connection endpoint."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Database port."
  value       = aws_db_instance.this.port
}

output "security_group_id" {
  description = "Security group protecting the database."
  value       = aws_security_group.this.id
}

output "db_identifier" {
  description = "Identifier of the RDS instance."
  value       = aws_db_instance.this.id
}
