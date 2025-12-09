variable "name" {
  description = "Name prefix for resources (e.g., 'shelfshack-dev')"
  type        = string
}

variable "domain_name" {
  description = "Name of the OpenSearch domain"
  type        = string
  default     = "shelfshack-search"
}

variable "engine_version" {
  description = "OpenSearch engine version (e.g., 'OpenSearch_2.11', 'OpenSearch_2.13')"
  type        = string
  default     = "OpenSearch_2.11"
}

variable "instance_type" {
  description = "Instance type for OpenSearch data nodes (e.g., 't3.small.search', 't3.medium.search')"
  type        = string
  default     = "t3.small.search"
}

variable "instance_count" {
  description = "Number of instances in the cluster (1-2 for dev, free tier friendly)"
  type        = number
  default     = 1
}

variable "vpc_id" {
  description = "VPC ID where OpenSearch will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs where OpenSearch nodes will be deployed"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access OpenSearch (e.g., ECS service security group)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "Optional list of CIDR blocks allowed to access OpenSearch (e.g., your IP for Kibana access)"
  type        = list(string)
  default     = []
}

variable "iam_role_arns" {
  description = "List of IAM role ARNs allowed to access OpenSearch (e.g., RentDeployRole, ECS task role)"
  type        = list(string)
}

variable "master_user_arn" {
  description = "Optional IAM user/role ARN to use as the OpenSearch master user. If not provided, uses the first role from iam_role_arns"
  type        = string
  default     = null
}

variable "ebs_volume_size" {
  description = "EBS volume size in GB for each node"
  type        = number
  default     = 10
}

variable "ebs_volume_type" {
  description = "EBS volume type (gp3, gp2, etc.)"
  type        = string
  default     = "gp3"
}

variable "automated_snapshot_start_hour" {
  description = "Hour in UTC when automated snapshots are taken (0-23)"
  type        = number
  default     = 0
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for OpenSearch (INDEX_SLOW_LOGS, SEARCH_SLOW_LOGS)"
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "create_service_linked_role" {
  description = "Whether to create the IAM service-linked role for OpenSearch (create once per account)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}






