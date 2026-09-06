terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "ap-south-1"
}

variable "github_repo" { default = "nikmar0808/enterprise-integration-project" }

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []
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
      # Matches a push from any branch of this repository — intentionally
      # broad, to align with the docker-build-push-* jobs running on every
      # push (not just develop/main) so the pipeline can be validated on a
      # feature branch before merging. StringLike's "*" matches across "/"
      # characters, so this also matches branch names containing slashes
      # (e.g. infra/phase2-aws-deployment).
      values = [
        "repo:${var.github_repo}:*"
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
      values   = ["organization:MyOtg:project:*:workspace:eai-project-infra:run_phase:*"]
    }
  }
}

resource "aws_iam_role" "tfc_run" {
  name               = "tfc-run-role"
  assume_role_policy = data.aws_iam_policy_document.tfc_trust.json
}

output "gha_deploy_role_arn" { value = aws_iam_role.gha_deploy.arn }
output "tfc_run_role_arn"    { value = aws_iam_role.tfc_run.arn }
