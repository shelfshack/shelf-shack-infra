variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the NLB"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the NLB"
  type        = list(string)
}

variable "opensearch_security_group_id" {
  description = "Security group ID of the OpenSearch container service (can be null initially)"
  type        = string
  default     = null
  nullable    = true
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access OpenSearch via NLB"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

