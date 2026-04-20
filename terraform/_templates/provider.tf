provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      App         = var.app
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
