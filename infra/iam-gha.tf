data "aws_iam_policy_document" "gha_permissions" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
      "ecr:PutImage", "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.java_gateway.arn, aws_ecr_repository.python_validator.arn]
  }
  statement {
    sid     = "DeployViaSSM"
    actions = ["ssm:SendCommand", "ssm:GetCommandInvocation"]
    resources = [
      "arn:aws:ec2:ap-south-1:*:instance/*",
      "arn:aws:ssm:ap-south-1::document/AWS-RunShellScript",
    ]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Name"
      values   = ["eai-project-host"]
    }
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  name   = "gha-deploy-permissions"
  role   = "gha-deploy-role"
  policy = data.aws_iam_policy_document.gha_permissions.json
}
