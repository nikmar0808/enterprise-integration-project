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
      "ecr:DescribeImages", # required by ci.yml's idempotency check before each push
    ]
    resources = [aws_ecr_repository.java_gateway.arn, aws_ecr_repository.python_validator.arn]
  }
  statement {
    sid       = "SSMSendCommandDocument"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:ap-south-1::document/AWS-RunShellScript"]
    # No resourceTag condition here — SSM documents aren't taggable in the way
    # EC2 instances are, and a real-world test found that combining an EC2
    # instance ARN and an SSM document ARN under one ssm:resourceTag/Name
    # condition in a single statement causes the whole statement to be denied
    # (the document resource can't satisfy a condition scoped to instance
    # tags). Splitting into separate statements — one per resource type, each
    # with the condition that actually applies to it — fixes this without
    # giving up the tag-based scoping on which instance can be targeted,
    # unlike simply removing the condition entirely.
  }
  statement {
    sid       = "SSMSendCommandTargetInstance"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:ap-south-1:*:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Name"
      values   = ["eai-project-host"]
    }
  }
  statement {
    sid = "SSMTrackingAndInstanceLookup"
    actions = [
      "ssm:GetCommandInvocation",
      # Required by the deploy job's status-polling loop, which resolves the
      # target instance ID via `aws ec2 describe-instances` before checking
      # command status — a real gap in the original policy, found only when
      # the deploy job actually ran.
      "ec2:DescribeInstances",
    ]
    # Both are describe/list-style read actions that AWS does not support
    # restricting by specific resource ARN — "*" is the correct, and only
    # valid, scope for these two actions specifically, not a broadening
    # of intent.
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  name   = "gha-deploy-permissions"
  role   = "gha-deploy-role"
  policy = data.aws_iam_policy_document.gha_permissions.json
}
