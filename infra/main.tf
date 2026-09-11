terraform {
  cloud {
    organization = "MyOtg"
    workspaces {
      name = "eai-aws-prod"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.5.0"
}
