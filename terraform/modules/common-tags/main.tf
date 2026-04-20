locals {
  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
    App         = "${var.app}-${var.environment}"
    ManagedBy   = "terraform"
    Stack       = var.stack
  }
}

output "tags" {
  description = "Common tag map for all resources"
  value       = local.tags
}
