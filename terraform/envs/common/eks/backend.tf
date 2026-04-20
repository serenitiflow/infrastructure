terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "serenity-dev-terraform-v2-state-692046683886"
    key            = "common/eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "serenity-dev-terraform-v2-locks"
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
      Stack       = "eks"
    }
  }
}
