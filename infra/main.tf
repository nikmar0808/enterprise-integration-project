terraform {
  # NEW — Terraform Cloud remote state (Phase 1, Step 5).
  # Replace the two placeholder values below with your real org/workspace names
  # from app.terraform.io. This block is safe to add right now — it does nothing
  # until you next run `terraform init`, which you're deliberately deferring.
  # When you do run it, Terraform will detect any existing local state and offer
  # to migrate it into this workspace automatically — nothing is lost either way.
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
