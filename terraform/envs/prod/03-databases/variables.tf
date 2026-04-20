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

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "postgres"
}

variable "aurora_instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.serverless"
}

variable "aurora_min_capacity" {
  description = "Minimum ACUs for Aurora Serverless v2"
  type        = number
  default     = 1
}

variable "aurora_max_capacity" {
  description = "Maximum ACUs for Aurora Serverless v2"
  type        = number
  default     = 8
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.small"
}

variable "aurora_scheduler_enabled" {
  description = "Enable Aurora scheduled stop/start"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Aurora backup retention period in days"
  type        = number
  default     = 30
}

variable "snapshot_retention_limit" {
  description = "Redis snapshot retention limit in days"
  type        = number
  default     = 7
}
