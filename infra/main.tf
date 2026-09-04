terraform {
  cloud {
    organization = "MyOtg"
    workspaces {
      name = "eai-project-infra"
    }
  }

  required_providers {
    # Specify the AWS provider and its version
    aws = {
      source  = "hashicorp/aws"
      # CHANGED: ~> instead of a pinned exact version, so you still get patch/minor
      # updates (bug fixes, new resource support) without silently jumping to a
      # potentially breaking major version like 7.x later.
      version = "~> 6.0"
    }
    # Could add other providers here if needed
  }
  # Specify the required Terraform version
  required_version = ">= 1.5.0"
}
