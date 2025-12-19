variable "name" {
  description = "Name prefix for resources (e.g., 'shelfshack-dev')"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where OpenSearch Dashboards will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs where OpenSearch Dashboards will be deployed"
  type        = list(string)
}

variable "ecs_cluster_name" {
  description = "ECS cluster name where OpenSearch Dashboards service will be deployed"
  type        = string
}

variable "opensearch_endpoint" {
  description = "OpenSearch endpoint URL (e.g., http://opensearch:9200 or http://internal-nlb:9200)"
  type        = string
}

variable "alb_security_group_ids" {
  description = "List of ALB security group IDs allowed to access Dashboards"
  type        = list(string)
  default     = []
}

variable "target_group_arn" {
  description = "Optional target group ARN for ALB integration"
  type        = string
  default     = null
  nullable    = true
}

variable "container_image" {
  description = "Docker image for OpenSearch Dashboards container"
  type        = string
  default     = "opensearchproject/opensearch-dashboards:2.11.0"
}

variable "cpu" {
  description = "Fargate CPU units for OpenSearch Dashboards container"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory in MB for OpenSearch Dashboards container"
  type        = number
  default     = 512
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for OpenSearch Dashboards container"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}


