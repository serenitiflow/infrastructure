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
  default     = "dev"
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
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Maximum ACUs for Aurora Serverless v2"
  type        = number
  default     = 2
}

variable "aurora_scheduler_enabled" {
  description = "Enable Aurora scheduled stop/start"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Aurora backup retention period in days"
  type        = number
  default     = 3
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to access databases directly (e.g. admin laptop IP)"
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Make Aurora publicly accessible (dev only - uses public subnets)"
  type        = bool
  default     = false
}
