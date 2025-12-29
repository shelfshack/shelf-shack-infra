output "endpoint" {
  description = "RDS connection endpoint (host:port)."
  value       = local.db_endpoint
}

output "address" {
  description = "RDS hostname."
  value       = local.db_address
}

output "port" {
  description = "Database port."
  value       = local.db_port
}

output "security_group_id" {
  description = "Security group protecting the database."
  value       = local.effective_security_group_id
}

output "db_identifier" {
  description = "Identifier of the RDS instance."
  value       = local.db_identifier
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = local.subnet_group_name
}

output "db_created" {
  description = "Whether the DB instance was created by this module (false if it already existed)."
  value       = local.should_create_db_instance
}

output "subnet_group_created" {
  description = "Whether the subnet group was created by this module."
  value       = local.should_create_subnet_group
}

output "security_group_created" {
  description = "Whether the security group was created by this module."
  value       = local.should_create_security_group
}
