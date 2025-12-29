variable "name" {
  description = "Base name/prefix for RDS resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC where the database will live."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group."
  type        = list(string)
}

variable "db_name" {
  description = "Initial database to create."
  type        = string
  default     = "shelfshack"
}

variable "master_username" {
  description = "Master username for PostgreSQL."
  type        = string
}

variable "master_password" {
  description = "Master password for PostgreSQL."
  type        = string
  sensitive   = true
}

variable "allocated_storage" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "17.6"
}

variable "instance_class" {
  description = "Instance size (free tier db.t3.micro)."
  type        = string
  default     = "db.t3.micro"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days to retain automated backups."
  type        = number
  default     = 0
}

variable "maintenance_window" {
  description = "Weekly maintenance window."
  type        = string
  default     = "Sun:05:00-Sun:06:00"
}

variable "backup_window" {
  description = "Preferred backup window."
  type        = string
  default     = null
}

variable "skip_final_snapshot" {
  description = "Skip snapshot on destroy."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Identifier for the final snapshot when skip_final_snapshot is false. If not provided, will use {name}-final-snapshot-{timestamp}."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Enable deletion protection."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply modifications immediately."
  type        = bool
  default     = true
}

variable "publicly_accessible" {
  description = "Expose DB to the public internet."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

# Resilience variables
variable "create_if_not_exists" {
  description = "If true, check if resources exist before creating. If they exist, use them instead of creating new ones. This prevents 'already exists' errors when Terraform state is lost."
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region for resource existence checks. Required when create_if_not_exists is true."
  type        = string
  default     = "us-east-1"
}
