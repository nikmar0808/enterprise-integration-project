terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "ap-south-1"
}

variable "github_repo" { default = "nikmar0808/enterprise-integration-aws" }
variable "github_username" { default = "nikmar0808" }
variable "github_repo_name" { default = "enterprise-integration-aws" }

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  # An alternate thumbprint was considered during troubleshooting and ruled
  # out — the actual root cause was GitHub's immutable subject claim format
  # change (see the sub condition below), unrelated to the OIDC provider's
  # certificate thumbprint.
}

data "aws_iam_policy_document" "gha_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Two patterns are matched, because GitHub Actions OIDC tokens can be in
      # either of two formats depending on when the repository was created:
      #
      # 1. The name-only format (repo:OWNER/REPO:ref:refs/heads/BRANCH), used
      #    by repositories created before GitHub's "Immutable Subject Claims"
      #    rollout (July 15, 2026).
      # 2. The immutable format (repo:OWNER@OWNER-ID/REPO@REPO-ID:ref:refs/
      #    heads/BRANCH), used automatically by repositories created, renamed,
      #    or transferred on or after that date — this repository included.
      #    The numeric owner/repo IDs are matched with "*" rather than
      #    hardcoded, since retrieving them requires a separate GitHub API
      #    call and StringLike's wildcard matches them regardless of value.
      #
      # Diagnostic note: this repository's tokens use format 2. Without the
      # second pattern below, every AssumeRoleWithWebIdentity call failed
      # with "Not authorized to perform sts:AssumeRoleWithWebIdentity"
      # regardless of which branch pattern was tried in format 1 alone — the
      # branch pattern was never the issue; the claim's overall shape was.
      # Keeping both patterns (rather than replacing format 1 outright) costs
      # nothing here and keeps this configuration portable to older,
      # non-immutable repositories if it's ever reused elsewhere.
      #
      # A second, separate distinction also matters here: jobs that declare
      # `environment: production` (the deploy job) get a sub claim shaped
      # differently from a plain branch push — repo:OWNER/REPO:environment:
      # NAME, not repo:OWNER/REPO:ref:refs/heads/BRANCH — regardless of which
      # branch triggered the run. The build/push jobs (no environment: set)
      # matched the ref-based patterns above and worked; the deploy job kept
      # failing OIDC until the environment-based patterns below were added,
      # for exactly this reason.
      values = [
        # Used by docker-build-push-* (regular push-triggered jobs, no environment: set)
        "repo:${var.github_repo}:ref:refs/heads/*",
        "repo:${var.github_username}@*/${var.github_repo_name}@*:ref:refs/heads/*",
        # Used by deploy (environment: production)
        "repo:${var.github_repo}:environment:production",
        "repo:${var.github_username}@*/${var.github_repo_name}@*:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "gha_deploy" {
  name               = "gha-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.gha_trust.json
}

resource "aws_iam_openid_connect_provider" "tfc" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
}

data "aws_iam_policy_document" "tfc_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.tfc.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:aud"
      values   = ["aws.workload.identity"]
    }
    condition {
      test     = "StringLike"
      variable = "app.terraform.io:sub"
      values   = ["organization:MyOtg:project:*:workspace:eai-aws-prod:run_phase:*"]
    }
  }
}

resource "aws_iam_role" "tfc_run" {
  name               = "tfc-run-role"
  assume_role_policy = data.aws_iam_policy_document.tfc_trust.json
}

output "gha_deploy_role_arn" { value = aws_iam_role.gha_deploy.arn }
output "tfc_run_role_arn"    { value = aws_iam_role.tfc_run.arn }
