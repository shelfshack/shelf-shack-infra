variable "name" {
  description = "Base name/prefix for OpenSearch EC2 resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where OpenSearch EC2 will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for OpenSearch EC2 instance"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID of the ECS service that needs to access OpenSearch"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Optional security group ID of bastion host for SSH access"
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type for OpenSearch"
  type        = string
  default     = "t3.micro"
}

variable "opensearch_image" {
  description = "OpenSearch Docker image name"
  type        = string
  default     = "opensearchproject/opensearch"
}

variable "opensearch_version" {
  description = "OpenSearch Docker image version/tag"
  type        = string
  default     = "latest"
}

variable "java_heap_size" {
  description = "Java heap size for OpenSearch (e.g., '512m', '1g')"
  type        = string
  default     = "512m"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for the EC2 instance"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

