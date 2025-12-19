variable "name" {
  description = "Name prefix for resources (e.g., 'shelfshack-dev')"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where OpenSearch container will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs where OpenSearch container will be deployed"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access OpenSearch (e.g., ECS service security group)"
  type        = list(string)
  default     = []
}

variable "ecs_cluster_name" {
  description = "ECS cluster name where OpenSearch service will be deployed"
  type        = string
}

variable "container_image" {
  description = "Docker image for OpenSearch container"
  type        = string
  default     = "opensearchproject/opensearch:2.11.0"
}

variable "cpu" {
  description = "Fargate CPU units for OpenSearch container (e.g. 512, 1024)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate memory in MB for OpenSearch container"
  type        = number
  default     = 1024
}

variable "java_opts" {
  description = "Java options for OpenSearch JVM"
  type        = string
  default     = "-Xms512m -Xmx512m"
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for OpenSearch container"
  type        = number
  default     = 30
}

variable "service_discovery_namespace_id" {
  description = "Optional AWS Service Discovery namespace ID for DNS-based service discovery. If not provided, service discovery is disabled."
  type        = string
  default     = null
  nullable    = true
}

variable "target_group_arn" {
  description = "Optional target group ARN for NLB integration"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

