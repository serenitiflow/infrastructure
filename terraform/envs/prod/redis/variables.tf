variable "project_name" {
  description = "Project name"
  type        = string
  default     = "serenity"
}

variable "app" {
  description = "Application name for resource tagging"
  type        = string
  default     = "serenity"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.small"
}

variable "snapshot_retention_limit" {
  description = "Redis snapshot retention limit in days"
  type        = number
  default     = 7
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to access Redis directly (e.g. admin laptop IP)"
  type        = list(string)
  default     = []
}
