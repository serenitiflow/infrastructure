terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "serenity-dev-terraform-state-eu-central-1-692046683886"
    key            = "shared/networking/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "serenity-dev-terraform-locks-eu-central-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      App         = var.app
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "networking"
    }
  }
}
