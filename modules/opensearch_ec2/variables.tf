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

variable "allowed_security_group_ids" {
  description = "List of security group IDs that should be allowed to access OpenSearch (e.g., ECS service security group)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks that should be allowed to access OpenSearch (e.g., VPC CIDR)"
  type        = list(string)
  default     = []
}

# Note: Security group rules are created separately in the main.tf file
# to avoid circular dependencies with the ECS service module

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

variable "opensearch_admin_password" {
  description = "Password for OpenSearch admin user (required for versions 2.12.0+). Must be at least 8 characters with uppercase, lowercase, digit, and special character."
  type        = string
  default     = "OpenSearch@2024!"  # Strong password meeting OpenSearch requirements
  sensitive   = true
}

variable "opensearch_admin_username" {
  description = "Username for OpenSearch admin user"
  type        = string
  default     = "admin"
}

variable "opensearch_security_disabled" {
  description = "Disable OpenSearch security plugin (set to false to enable password authentication)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

