variable "project_name" {
  description = "Project name"
  type        = string
  default     = "serenity"
}

variable "app" {
  description = "Application name"
  type        = string
  default     = "serenity"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "common"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
