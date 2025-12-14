variable "name" {
  description = "Base name for ECS resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ECS resources run."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets used by the load balancer."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets used by the ECS service."
  type        = list(string)
}

variable "service_subnet_ids" {
  description = "Optional override for the ECS service subnets (defaults to private when behind an ALB, public otherwise)."
  type        = list(string)
  default     = []
}

variable "container_image" {
  description = "Full image URI (e.g. ECR repo + tag)."
  type        = string
}

variable "container_port" {
  description = "Container port exposed through the ALB."
  type        = number
  default     = 3000
}

variable "cpu" {
  description = "CPU units for the task definition."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memory (MB) for the task definition."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Number of Fargate tasks to run."
  type        = number
  default     = 1
}

variable "assign_public_ip" {
  description = "Assign public IPs to Fargate tasks."
  type        = bool
  default     = false
}

variable "enable_load_balancer" {
  description = "Controls whether an external Application Load Balancer is created."
  type        = bool
  default     = true
}

variable "environment_variables" {
  description = "Plain environment variables for the container."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  description = "Secrets injected into the container from AWS Secrets Manager or SSM Parameter Store."
  type = list(object({
    name       = string
    value_from = string
  }))
  default = []
}

variable "health_check_path" {
  description = "HTTP path used by the ALB health check."
  type        = string
  default     = "/"
}

variable "listener_port" {
  description = "External listener port for HTTP."
  type        = number
  default     = 80
}

variable "enable_https" {
  description = "Provision an HTTPS listener and redirect HTTP to HTTPS."
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Optional Route53 hosted zone ID to create an alias record to the ALB."
  type        = string
  default     = null
}

variable "route53_record_name" {
  description = "Record name created in the hosted zone (accepts bare or fully-qualified strings)."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener."
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "Retention period for CloudWatch Logs."
  type        = number
  default     = 30
}

variable "deployment_maximum_percent" {
  description = "Upper limit for the number of running tasks during a deployment."
  type        = number
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower limit for running tasks during a deployment."
  type        = number
  default     = 100
}

variable "enable_execute_command" {
  description = "Enable ECS Exec on the service."
  type        = bool
  default     = false
}

variable "task_role_managed_policies" {
  description = "List of IAM managed policy ARNs attached to the task role."
  type        = list(string)
  default     = []
}

variable "additional_service_security_group_ids" {
  description = "Optional extra security group IDs attached to the ECS service ENIs."
  type        = list(string)
  default     = []
}

variable "command" {
  description = "Optional command override for the container."
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Tags applied to ECS resources."
  type        = map(string)
  default     = {}
}

variable "force_new_deployment" {
  description = "Force ECS to start a new deployment on every Terraform apply."
  type        = bool
  default     = false
}

variable "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain to grant access to. If provided, creates an inline policy on the task role."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_opensearch_access" {
  description = "Enable OpenSearch access policy for the task role. Set to true if opensearch_domain_arn is provided."
  type        = bool
  default     = false
}

variable "s3_bucket_name" {
  description = "S3 bucket name for file uploads. If provided, grants S3 permissions to task role."
  type        = string
  default     = null
}
