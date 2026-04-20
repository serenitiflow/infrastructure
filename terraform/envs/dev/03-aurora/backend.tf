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
    bucket         = "serenity-dev-terraform-state-eu-central-1-692046683886"
    key            = "dev/aurora/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "serenity-dev-terraform-locks-eu-central-1"
    encrypt        = true
  }
}
