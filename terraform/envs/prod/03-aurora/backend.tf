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
    bucket         = "serenity-prod-terraform-v2-state-eu-central-1-692046683886"
    key            = "prod/aurora/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "serenity-prod-terraform-v2-locks-eu-central-1"
    encrypt        = true
  }
}
