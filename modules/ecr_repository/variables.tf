variable "name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "image_tag_mutability" {
  description = "Whether image tags are mutable or immutable."
  type        = string
  default     = "IMMUTABLE"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE"
  }
}

variable "scan_on_push" {
  description = "Enable image scan on push."
  type        = bool
  default     = true
}

variable "lifecycle_policy" {
  description = "Optional lifecycle policy JSON to control image retention."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional tags for the repository."
  type        = map(string)
  default     = {}
}

variable "create_if_not_exists" {
  description = "If true, check if repository exists before creating. If repository exists, use it instead of creating a new one. This prevents 'RepositoryAlreadyExistsException' errors."
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "If true, allows deleting the repository even if it contains images."
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region for the ECR repository. Required for existence check."
  type        = string
  default     = "us-east-1"
}
