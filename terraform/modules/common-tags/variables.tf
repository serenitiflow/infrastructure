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
  default     = "dev"
}

variable "stack" {
  description = "Stack/component name (e.g., networking, eks, aurora, redis)"
  type        = string
}
