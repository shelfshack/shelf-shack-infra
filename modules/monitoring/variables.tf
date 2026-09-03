variable "app_name" {
  description = "Application name used to prefix alarm names."
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the alerts topic. Empty string skips the subscription (subscribe manually in the console)."
  type        = string
  default     = ""
}

variable "ecs_cluster_name" {
  description = "ECS cluster name for CPU/memory alarms."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name for CPU/memory alarms."
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS instance identifier for storage/CPU alarms. Empty string skips RDS alarms."
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for 5xx alarms. Null skips ALB alarms."
  type        = string
  default     = null
}

variable "rds_free_storage_threshold_bytes" {
  description = "Alarm when RDS free storage drops below this many bytes (default 2 GiB)."
  type        = number
  default     = 2147483648
}

variable "tags" {
  description = "Tags applied to all monitoring resources."
  type        = map(string)
  default     = {}
}
