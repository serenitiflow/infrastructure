variable "alias_name" {
  description = "KMS alias name (e.g., serenity-dev-secrets)"
  type        = string
}

variable "secret_name" {
  description = "Secrets Manager secret name (e.g., serenity/dev/database/credentials)"
  type        = string
}

variable "environment" {
  description = "Environment name for random_password keeper"
  type        = string
}

variable "password_length" {
  description = "Length of generated random password"
  type        = number
  default     = 32
}

variable "service" {
  description = "Service name for KMS key description"
  type        = string
  default     = "database"
}

variable "tags" {
  description = "Tags to apply to KMS key and secret"
  type        = map(string)
  default     = {}
}
