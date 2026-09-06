data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_instance_role" {
  name               = "eai-ec2-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_runtime_permissions" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = [aws_ecr_repository.java_gateway.arn, aws_ecr_repository.python_validator.arn]
  }
  statement {
    sid     = "ReadOwnSecrets"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.rds_password.arn,
      aws_ssm_parameter.api_security_token.arn,
    ]
  }
  statement {
    sid       = "DecryptSecureStrings"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:ap-south-1:*:alias/aws/ssm"]
  }
}

resource "aws_iam_role_policy" "ec2_runtime" {
  name   = "ec2-runtime-permissions"
  role   = aws_iam_role.ec2_instance_role.name
  policy = data.aws_iam_policy_document.ec2_runtime_permissions.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "eai-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
}
