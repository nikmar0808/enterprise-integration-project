# Deployment Guide

This document describes how to deploy this project to an independent AWS account. It assumes the repository has been cloned and the local quickstart in [`README.md`](../README.md) has been verified. Design rationale is in [`ARCHITECTURE.md`](ARCHITECTURE.md) and is not repeated here.

**Prerequisites**

| Requirement | Notes |
|---|---|
| AWS account | Free-tier eligibility for RDS and API Gateway applies only within the account's first 12 months |
| GitHub repository (a fork or clone of this project) | Actions and Environments must be enabled |
| Terraform Cloud account and organization | Free tier is sufficient |
| AWS CLI ≥ 2.32.0 | Required for the `aws login` command used in identity bootstrap |
| Terraform CLI ≥ 1.5.0 | |
| Docker and Docker Compose | For local verification |

## Placeholder reference

Every command block below uses the placeholders in this table. Replace all occurrences before running a command.

| Placeholder | Example value | How to obtain it |
|---|---|---|
| `<AWS_ACCOUNT_ID>` | `123456789012` | Run `aws sts get-caller-identity --query Account --output text` once any AWS credential is configured |
| `<AWS_REGION>` | `ap-south-1` | The AWS region chosen for this deployment; must be used consistently in every command and Terraform file |
| `<GITHUB_ORG>` | `octocat` | The GitHub username or organization that owns the repository, visible in its URL |
| `<REPO_NAME>` | `enterprise-integration-project` | The repository name, visible in its URL |
| `<TFC_ORG>` | `my-tfc-org` | The Terraform Cloud organization name, shown at the top of the Terraform Cloud web interface after sign-in |
| `<TFC_WORKSPACE>` | `eai-project-infra` | A workspace name chosen when creating the Terraform Cloud workspace for this project |
| `<EC2_TAG_NAME>` | `eai-project-host` | A `Name` tag value chosen for the EC2 instance in Terraform; used to target deployment commands |
| `<MFA_DEVICE_ARN>` | `arn:aws:iam::123456789012:mfa/terraform-admin` | Shown in the IAM console under the bootstrap user's Security Credentials, after an MFA device is registered |

---

## Phase 0 — Local Development Verification

This step confirms the application layer works correctly, independently of any AWS resource, before proceeding to cloud deployment. `docker-compose.dev.yml` already exists in the cloned repository (created as part of the project's container-hardening work); it is shown here in full for reference and to confirm its role before the production-only `infra/docker-compose.prod.yml` is introduced in Phase 3.

**Existing file — no changes required:** `docker-compose.dev.yml` (repository root).

```yaml
networks:
  eai-mesh:
    driver: bridge
volumes:
  postgres_persistent_engine_data:
services:
  postgres-db:
    image: postgres:16-alpine
    container_name: postgres-db
    restart: always
    command: postgres -c log_timezone=Asia/Kolkata -c timezone=Asia/Kolkata
    environment:
      - POSTGRES_USER=smart_meter_admin
      - POSTGRES_PASSWORD=smart_meter_password_2026
      - POSTGRES_DB=smart_meter_warehouse
      - TZ=Asia/Kolkata
    ports: ["5432:5432"]
    volumes:
      - postgres_persistent_engine_data:/var/lib/postgresql/data
    networks: [eai-mesh]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U smart_meter_admin -d smart_meter_warehouse"]
      interval: 5s
      timeout: 5s
      retries: 10

  python-validator:
    build: { context: ./02-python-transformation-api, dockerfile: Dockerfile }
    container_name: python-validator
    restart: always
    environment:
      - API_SECURITY_TOKEN=EAI-SECRET-SECURE-KEY-2026
      - DATABASE_URL=postgresql+psycopg://smart_meter_admin:smart_meter_password_2026@postgres-db:5432/smart_meter_warehouse
      - TZ=Asia/Kolkata
    ports: ["8082:8082"]
    depends_on:
      postgres-db: { condition: service_healthy }
    networks: [eai-mesh]

  java-gateway:
    build: { context: ./01-java-ingestion-service, dockerfile: Dockerfile }
    container_name: java-gateway
    restart: always
    environment:
      - SERVER_PORT=8081
      - INTEGRATION_PYTHON_BASE-URL=http://python-validator:8082
      - INTEGRATION_PYTHON_AUTH-TOKEN=EAI-SECRET-SECURE-KEY-2026
      - TZ=Asia/Kolkata
      - JAVA_OPTS=-Duser.timezone=Asia/Kolkata
    ports: ["8081:8081"]
    depends_on: [python-validator]
    networks: [eai-mesh]
```

**Verify:**

```bash
# Run from: <repo-root>
docker compose -f docker-compose.dev.yml up --build -d
docker compose -f docker-compose.dev.yml ps
curl http://localhost:8081/health
```
```powershell
# PowerShell equivalent — run from: <repo-root>
docker compose -f docker-compose.dev.yml up --build -d
docker compose -f docker-compose.dev.yml ps
Invoke-RestMethod -Uri http://localhost:8081/health
```

**Expected result:** all three services report `running` or `healthy`; the health check returns `{"status":"UP"}`. Once confirmed, the local stack can be stopped (`docker compose -f docker-compose.dev.yml down`) before proceeding — Phase 1 onward does not depend on it remaining up.

---

## Phase 1 — Identity and Access Bootstrap

### 1.1 Local bootstrap of OIDC trust relationships

`aws login` (AWS CLI ≥ 2.32.0) provides a browser-based flow that reuses standard console authentication (root, IAM user, or federation) to issue short-lived terminal credentials, without creating a static access key. This is distinct from IAM Identity Center; AWS documentation directs Identity Center users to `aws sso login` instead.

This step establishes the OIDC trust relationships that all subsequent automation depends on, and is the only step in this deployment performed with a human-authenticated local credential.

**Procedure:**

1. In the AWS Console, create an IAM user named `terraform-admin` (non-root). Attach the `SignInLocalDevelopmentAccess` managed policy (required for `aws login`), plus sufficient permissions to create IAM OIDC providers and roles.

2. Configure a named profile:

```bash
# Run from: anywhere (this edits a global AWS CLI config file)
# File: ~/.aws/config
```
```ini
[profile terraform-admin]
region = <AWS_REGION>
output = json
```

3. Authenticate:

```bash
# Run from: <repo-root>
aws login --profile terraform-admin
aws sts get-caller-identity --profile terraform-admin
```
```powershell
# PowerShell equivalent — run from: <repo-root>
aws login --profile terraform-admin
aws sts get-caller-identity --profile terraform-admin
```

4. Apply the bootstrap Terraform configuration (local state, run outside Terraform Cloud — see `ARCHITECTURE.md` Appendix A.3 for why):

`infra/bootstrap/main.tf` — a new file, in a new `bootstrap/` subdirectory created for this step. This is deliberately a separate Terraform root module from the project's main configuration, with its own local state (see `ARCHITECTURE.md` Appendix A.3 for why). It is not the same file as `infra/main.tf`, introduced in Phase 2, which belongs to the main, Terraform-Cloud-backed configuration alongside `eai-project.tf` and the other resource files. Both files exist in the repository, at different paths, serving different purposes:

| File | Location | State | Purpose |
|---|---|---|---|
| `main.tf` | `infra/bootstrap/` | Local (this file only) | One-time creation of the two OIDC providers and the two IAM role shells |
| `main.tf` | `infra/` | Terraform Cloud (shared with all other files in `infra/`) | Backend and provider configuration for the main resource set created in Phase 2 |

```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "<AWS_REGION>"
  # Credentials are supplied via exported environment variables (step 5),
  # not a profile referencing SSO or Identity Center.
}

variable "github_repo" { default = "<GITHUB_ORG>/<REPO_NAME>" }

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
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
        "repo:${var.github_repo}:ref:refs/heads/*",
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
      values   = ["organization:<TFC_ORG>:project:*:workspace:<TFC_WORKSPACE>:run_phase:*"]
    }
  }
}

resource "aws_iam_role" "tfc_run" {
  name               = "tfc-run-role"
  assume_role_policy = data.aws_iam_policy_document.tfc_trust.json
}

output "gha_deploy_role_arn" { value = aws_iam_role.gha_deploy.arn }
output "tfc_run_role_arn"    { value = aws_iam_role.tfc_run.arn }
```

5. Apply:

```bash
# Run from: <repo-root>/infra/bootstrap
cd infra/bootstrap
terraform init
eval $(aws configure export-credentials --profile terraform-admin --format env)
terraform plan
terraform apply
```
```powershell
# PowerShell equivalent — run from: <repo-root>\infra\bootstrap
cd infra\bootstrap
terraform init

$creds = aws configure export-credentials --profile terraform-admin --format process | ConvertFrom-Json
$env:AWS_ACCESS_KEY_ID     = $creds.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $creds.SecretAccessKey
$env:AWS_SESSION_TOKEN     = $creds.SessionToken

terraform plan
terraform apply
```

**Expected result:** Terraform outputs `gha_deploy_role_arn` and `tfc_run_role_arn`. Record both values; they are required in step 1.2 and Phase 2.

**Any future edit to this file — including changing the `sub` condition's branch pattern — has no effect on AWS until `terraform apply` is re-run inside `infra/bootstrap/` specifically, with credentials re-exported.** This is a separate root module with its own local state; editing the `.tf` file alone does nothing. Before assuming a trust-policy change didn't work, re-run `terraform plan` here first and confirm it actually shows a diff — if it reports no changes, the edit isn't being picked up, and the live AWS trust policy is unaffected regardless of what the file currently says. The definitive ground truth is always the AWS Console — IAM → Roles → `gha-deploy-role` → Trust relationships — not this file.

### 1.2 Terraform Cloud configuration

In the Terraform Cloud web interface, workspace `<TFC_WORKSPACE>` (organization `<TFC_ORG>`) → Variables → add as **workspace environment variables** (not marked sensitive; they contain no secret material):

| Key | Value |
|---|---|
| `TFC_AWS_PROVIDER_AUTH` | `true` |
| `TFC_AWS_RUN_ROLE_ARN` | `<tfc_run_role_arn from step 1.1>` |

### 1.3 Provider configuration

The AWS provider block lives in `infra/eai-project.tf`, alongside the rest of the network and compute resources — it is shown as part of that file's complete, consolidated listing in Phase 2, Section 2.6, rather than as an isolated fragment here, to avoid the same file's contents being split across two places in this document.

---

## Phase 2 — AWS Resource Provisioning

This phase is executed through Terraform Cloud (recommended: connect the workspace to the GitHub repository under Workspace → Settings → Version Control, so a push touching `infra/` triggers a plan/apply automatically) or locally via `aws login` with the workspace's execution mode temporarily set to "Local."

**Existing file — edit, do not recreate:** `infra/main.tf` (at the `infra/` root, not `infra/bootstrap/main.tf` from Phase 1 — the two are separate files with separate purposes; see the comparison table in Section 1.1). This file defines the Terraform Cloud backend and required providers for the main configuration. It already exists in the cloned repository; only the two highlighted values need to change to point at your own Terraform Cloud organization and workspace.

```hcl
terraform {
  cloud {
    organization = "<TFC_ORG>"
    workspaces {
      name = "<TFC_WORKSPACE>"
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
```

`networking.tf`, `ecr.tf`, `rds.tf`, `iam-gha.tf`, `iam-ec2.tf`, and `api-gateway.tf` are new files, created fresh in this phase. `infra/eai-project.tf` (Section 2.6) is the one exception: it already exists in the cloned repository, containing the VPC and first subnet that the new resources in this phase depend on, so it is shown here in full — incorporating this phase's changes — rather than as a diff.

### 2.1 Second subnet

Amazon RDS requires a DB subnet group spanning at least two Availability Zones.

`infra/networking.tf`:
```hcl
resource "aws_subnet" "subnet-2" {
  vpc_id            = aws_vpc.enterprise_network.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "<AWS_REGION>b"

  tags = { Name = "Primary-Subnet-2", Environment = "Production" }
}
```

### 2.2 Container registry

`infra/ecr.tf`:
```hcl
resource "aws_ecr_repository" "java_gateway" {
  name                 = "eai-java-gateway"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "python_validator" {
  name                 = "eai-python-validator"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "java_gateway" {
  repository = aws_ecr_repository.java_gateway.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1, description = "Keep last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "python_validator" {
  repository = aws_ecr_repository.python_validator.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1, description = "Keep last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
```

### 2.3 RDS for PostgreSQL

`infra/rds.tf`:
```hcl
resource "random_password" "rds_master" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "rds_password" {
  name  = "/eai-project/rds/master_password"
  type  = "SecureString"
  value = random_password.rds_master.result
}

resource "aws_ssm_parameter" "api_security_token" {
  name  = "/eai-project/api/security_token"
  type  = "SecureString"
  value = "REPLACE-WITH-A-GENERATED-TOKEN"
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "eai-rds-subnet-group"
  subnet_ids = [aws_subnet.subnet-1.id, aws_subnet.subnet-2.id]
}

resource "aws_security_group" "db_sg" {
  name        = "eai-db-sg"
  description = "PostgreSQL access restricted to the application security group"
  vpc_id      = aws_vpc.enterprise_network.id

  ingress {
    description     = "PostgreSQL from application tier only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "eai-db-sg" }
}

resource "aws_db_instance" "smart_meter_db" {
  identifier               = "eai-smart-meter-db"
  engine                   = "postgres"
  engine_version           = "16"
  instance_class           = "db.t4g.micro"
  allocated_storage        = 20
  db_name                  = "smart_meter_warehouse"
  username                 = "smart_meter_admin"
  password                 = random_password.rds_master.result
  db_subnet_group_name     = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids   = [aws_security_group.db_sg.id]
  publicly_accessible      = false
  multi_az                 = false
  skip_final_snapshot      = true
  backup_retention_period  = 1

  tags = { Name = "eai-smart-meter-db" }
}

output "rds_endpoint" { value = aws_db_instance.smart_meter_db.address }
```

**Free-tier note:** verify the account's remaining free-tier window (AWS Console → Billing → Free Tier) before applying this resource, and record the date after which billing applies.

### 2.4 IAM policy: CI deployment role

`infra/iam-gha.tf`:
```hcl
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
      "arn:aws:ec2:<AWS_REGION>:*:instance/*",
      "arn:aws:ssm:<AWS_REGION>::document/AWS-RunShellScript",
    ]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Name"
      values   = ["<EC2_TAG_NAME>"]
    }
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  name   = "gha-deploy-permissions"
  role   = "gha-deploy-role"
  policy = data.aws_iam_policy_document.gha_permissions.json
}
```

### 2.5 EC2 instance profile

`infra/iam-ec2.tf`:
```hcl
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
    resources = ["arn:aws:kms:<AWS_REGION>:*:alias/aws/ssm"]
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
```

### 2.6 Complete `infra/eai-project.tf`

This file already exists in the cloned repository, containing the VPC, the first subnet, and the compute instance. The listing below is the **complete file after this phase's changes** — shown in full, rather than as a diff, so there is no ambiguity about what surrounding content to preserve. Three changes are called out inline: the provider block no longer references a profile or SSO login, the SSH ingress rule and key pair are removed in favor of SSM, and the instance gains an IAM instance profile.

```hcl
provider "aws" {
  region = "<AWS_REGION>"
  # Credentials are supplied by Terraform Cloud's dynamic provider credentials
  # (OIDC, via tfc-run-role) during remote execution. For local execution,
  # `aws login` combined with `aws configure export-credentials` is used —
  # never a profile referencing SSO or Identity Center.
}

resource "aws_vpc" "enterprise_network" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name        = "Primary-Enterprise-VPC"
    Environment = "Production"
    Compliance  = "Strict-Regulated"
  }
}

resource "aws_subnet" "subnet-1" {
  vpc_id                  = aws_vpc.enterprise_network.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "<AWS_REGION>a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "Primary-Subnet-1"
    Environment = "Production"
    Compliance  = "Strict-Regulated"
  }
}

resource "aws_internet_gateway" "enterprise_igw" {
  vpc_id = aws_vpc.enterprise_network.id
  tags   = { Name = "Primary-Enterprise-IGW" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.enterprise_network.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.enterprise_igw.id
  }

  tags = { Name = "Primary-Public-Route-Table" }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "app_sg" {
  name        = "eai-app-sg"
  description = "Ingestion gateway public; internal service internal-only; SSH removed in favor of SSM"
  vpc_id      = aws_vpc.enterprise_network.id

  # Port 22 removed from the baseline configuration. SSM Session Manager,
  # via the instance profile below, provides shell access over the AWS API
  # using IAM credentials — no inbound SSH port or key pair is required.

  ingress {
    description = "Ingestion gateway"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Port 8082 (transformation service) intentionally not opened — it is
  # reached only by the ingestion service over the internal Docker network.

  egress {
    description = "Allow all outbound (Docker image pulls, package updates, AWS API calls)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "eai-app-sg" }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# The aws_key_pair resource from the baseline configuration is removed
# entirely — no SSH key pair is required once SSM replaces SSH access.

resource "aws_instance" "sandbox-1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.subnet-1.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  # key_name removed — see note above.

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    mkdir -p /opt/eai
  EOF

  tags = { Name = "<EC2_TAG_NAME>" }
}

output "instance_public_ip" { value = aws_instance.sandbox-1.public_ip }
output "instance_id"        { value = aws_instance.sandbox-1.id }
```

### 2.7 API Gateway

`infra/api-gateway.tf`:
```hcl
resource "aws_apigatewayv2_api" "eai_http_api" {
  name          = "eai-project-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "java_gateway" {
  api_id             = aws_apigatewayv2_api.eai_http_api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "http://${aws_instance.sandbox-1.public_ip}:8081/{proxy}"
}

resource "aws_apigatewayv2_route" "proxy_route" {
  api_id    = aws_apigatewayv2_api.eai_http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.java_gateway.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.eai_http_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

output "api_gateway_url" { value = aws_apigatewayv2_api.eai_http_api.api_endpoint }
```

**Scoping limitation:** `HTTP_PROXY` integration to a public IP does not correspond to a published, stable AWS IP range, so this configuration does not remove the compute instance's public port exposure. See `ARCHITECTURE.md`, Section 4, for the VPC Link successor.

### 2.8 Commit and apply

`infra/main.tf` already exists in the cloned repository and needs only its Terraform Cloud organization and workspace values updated (Section 2.1) — it is not a new file. It is still included in the commit below because Terraform cannot apply successfully without the backend configuration and at least one resource file both being present together.

```bash
# Run from: <repo-root>/infra
cd infra
git add main.tf networking.tf ecr.tf rds.tf iam-gha.tf iam-ec2.tf api-gateway.tf eai-project.tf
git commit -m "infra: RDS, API Gateway, SSM Parameter Store secrets, OIDC-scoped IAM, SSM-based EC2 access"
git push origin <branch-name>
```
```powershell
# PowerShell equivalent — run from: <repo-root>\infra
cd infra
git add main.tf networking.tf ecr.tf rds.tf iam-gha.tf iam-ec2.tf api-gateway.tf eai-project.tf
git commit -m "infra: RDS, API Gateway, SSM Parameter Store secrets, OIDC-scoped IAM, SSM-based EC2 access"
git push origin <branch-name>
```

### 2.9 Confirm the apply and record its outputs

Pushing the commit above does **not** reliably queue a Terraform Cloud run — that depends entirely on the workspace's VCS connection actually being configured (Settings → Version Control should not show "Not Connected"; if it does, no push will ever trigger a run there, regardless of branch). It **will**, however, trigger this repository's `.github/workflows/ci.yml` if that file already exists on the pushed branch, since GitHub Actions triggers on every push matching `on: push: branches: ["**"]` regardless of which files actually changed — an infra-only commit still fires the full CI workflow. The two systems trigger independently of each other and of this document's phase numbering.

Given that, apply this phase locally rather than depending on an automatic Terraform Cloud run:

**The bootstrap IAM user needs the AWS-managed [`AdministratorAccess`](https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/policies/details/arn%3Aaws%3Aiam%3A%3Aaws%3Apolicy%2FAdministratorAccess) policy attached** for this apply to succeed — this phase creates resources across many services (EC2, RDS, IAM, API Gateway, SSM, ECR), and a hand-crafted narrower policy covering all of them is disproportionate effort for a one-time local bootstrap identity that never holds a standing access key (see Section 1.1's rationale for why that trade-off is acceptable here).

```powershell
cd infra
aws login --profile terraform-admin
aws sts get-caller-identity --profile terraform-admin
$creds = aws configure export-credentials --profile terraform-admin --format process | ConvertFrom-Json
$env:AWS_ACCESS_KEY_ID     = $creds.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $creds.SecretAccessKey
$env:AWS_SESSION_TOKEN     = $creds.SessionToken
terraform plan
terraform apply
terraform output -raw rds_endpoint
```

Record the `rds_endpoint` output. **This value is required as the `RDS_ENDPOINT` GitHub Actions variable in Phase 3 — do not proceed to that step until it has been retrieved.**

---

## Phase 3 — CI/CD Pipeline

This phase introduces a second Docker Compose file, distinct from the one at the repository root used for local development:

| | `docker-compose.dev.yml` (repository root) | `infra/docker-compose.prod.yml` (created below) |
|---|---|---|
| Used by | Local development | The deployed EC2 instance |
| Application images | Built from source | Pulled from Amazon ECR |
| PostgreSQL | Containerized, included in this file | Not present — Amazon RDS is used instead |
| Secrets | Hardcoded literal values (a disposable local database) | Injected from an `.env` file assembled from SSM Parameter Store at deploy time |

The two files diverge on every one of these points, which is why they are kept separate rather than combined with conditionals.

**Create `infra/docker-compose.prod.yml`** with the following content. This file is referenced by the deployment workflow created next, so it must exist first:

```yaml
networks:
  eai-mesh:
    driver: bridge
services:
  python-validator:
    image: ${ECR_REGISTRY}/eai-python-validator:${IMAGE_TAG}
    restart: always
    environment:
      - API_SECURITY_TOKEN=${API_SECURITY_TOKEN}
      - DATABASE_URL=${DATABASE_URL}
      - TZ=Asia/Kolkata
    networks: [eai-mesh]
  java-gateway:
    image: ${ECR_REGISTRY}/eai-java-gateway:${IMAGE_TAG}
    restart: always
    environment:
      - SERVER_PORT=8081
      - INTEGRATION_PYTHON_BASE-URL=http://python-validator:8082
      - INTEGRATION_PYTHON_AUTH-TOKEN=${API_SECURITY_TOKEN}
      - TZ=Asia/Kolkata
      - JAVA_OPTS=-Duser.timezone=Asia/Kolkata
    ports: ["8081:8081"]
    depends_on: [python-validator]
    networks: [eai-mesh]
```

**Create `.github/workflows/ci.yml`** with the following content:

```yaml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:
    branches: [main, develop]

permissions:
  contents: read

env:
  AWS_REGION: <AWS_REGION>
  ECR_REGISTRY: ${{ vars.AWS_ACCOUNT_ID }}.dkr.ecr.<AWS_REGION>.amazonaws.com
  # Avoids the common ghcr.io anonymous-pull rate limit that causes Trivy's
  # vulnerability DB download to fail in CI; AWS's public ECR mirror is not
  # subject to the same limit.
  TRIVY_DB_REPOSITORY: public.ecr.aws/aquasecurity/trivy-db
  TRIVY_JAVA_DB_REPOSITORY: public.ecr.aws/aquasecurity/trivy-java-db

jobs:
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      # Pinned to a released version rather than @main — a floating branch
      # reference for a security-scanning action is itself a supply-chain risk.
      - uses: trufflesecurity/trufflehog@v3.94.1
        with: { extra_args: --only-verified }

  dependency-scan:
    runs-on: ubuntu-latest
    # Required by github/codeql-action/upload-sarif below; without it the
    # upload step fails regardless of whether the SARIF file exists.
    permissions: { contents: read, security-events: write }
    steps:
      - uses: actions/checkout@v4
      # Pinned to a specific release, not @master. @master is a materially
      # higher risk for this action specifically: aquasecurity/trivy-action
      # tags before 0.35.0 were affected by a real supply-chain compromise
      # (GHSA-69fq-xp46-6x23); 0.35.0 was confirmed clean by the maintainers.
      - uses: aquasecurity/trivy-action@0.35.0
        with:
          scan-type: fs
          scan-ref: .
          severity: CRITICAL,HIGH
          exit-code: 1
          format: sarif
          output: trivy-fs-results.sarif
      # Guards against uploading a file that was never written — e.g. if the
      # Trivy DB pull itself failed rather than the scan simply finding
      # vulnerabilities, no SARIF file exists and this step is skipped
      # instead of erroring.
      - if: always() && hashFiles('trivy-fs-results.sarif') != ''
        uses: github/codeql-action/upload-sarif@v3
        with: { sarif_file: trivy-fs-results.sarif }

  java-build-test:
    needs: [secret-scan, dependency-scan]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # cache: maven persists ~/.m2/repository between runs, keyed on
      # pom.xml. Without it, every run — including repeated re-runs while
      # debugging — re-downloads the full dependency tree from Maven
      # Central, which is what triggers 429 rate-limiting under repeated use.
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "21", cache: maven }
      - working-directory: 01-java-ingestion-service
        run: mvn -B verify

  python-build-test:
    needs: [secret-scan, dependency-scan]
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: smart_meter_admin
          POSTGRES_PASSWORD: smart_meter_password_2026
          POSTGRES_DB: smart_meter_warehouse
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.14", cache: pip }
      - working-directory: 02-python-transformation-api
        run: pip install -r requirements.txt
      - working-directory: 02-python-transformation-api
        env:
          DATABASE_URL: postgresql+psycopg://smart_meter_admin:smart_meter_password_2026@localhost:5432/smart_meter_warehouse
        run: pytest tests

  docker-build-push-java:
    needs: java-build-test
    # Runs on a push to ANY branch (but not on pull_request-triggered runs,
    # which don't need an image pushed) — this is what lets the full
    # build/scan/push pipeline be validated on a feature branch, before
    # merging to develop/main. Only the deploy job below is restricted to
    # main; that is the actual production boundary.
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions: { contents: read, id-token: write }
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with: { role-to-assume: "arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/gha-deploy-role", aws-region: "${{ env.AWS_REGION }}" }
      - uses: aws-actions/amazon-ecr-login@v2
      - run: docker build -t $ECR_REGISTRY/eai-java-gateway:${{ github.sha }} ./01-java-ingestion-service
      - uses: aquasecurity/trivy-action@0.35.0
        with: { image-ref: "${{ env.ECR_REGISTRY }}/eai-java-gateway:${{ github.sha }}", severity: "CRITICAL,HIGH", exit-code: 1 }
      - run: docker push $ECR_REGISTRY/eai-java-gateway:${{ github.sha }}

  docker-build-push-python:
    needs: python-build-test
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions: { contents: read, id-token: write }
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with: { role-to-assume: "arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/gha-deploy-role", aws-region: "${{ env.AWS_REGION }}" }
      - uses: aws-actions/amazon-ecr-login@v2
      - run: docker build -t $ECR_REGISTRY/eai-python-validator:${{ github.sha }} ./02-python-transformation-api
      - uses: aquasecurity/trivy-action@0.35.0
        with: { image-ref: "${{ env.ECR_REGISTRY }}/eai-python-validator:${{ github.sha }}", severity: "CRITICAL,HIGH", exit-code: 1 }
      - run: docker push $ECR_REGISTRY/eai-python-validator:${{ github.sha }}

  deploy:
    needs: [docker-build-push-java, docker-build-push-python]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    permissions: { contents: read, id-token: write }
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with: { role-to-assume: "arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/gha-deploy-role", aws-region: "${{ env.AWS_REGION }}" }
      - name: Deploy via SSM
        run: |
          COMPOSE_B64=$(base64 -w0 infra/docker-compose.prod.yml)
          COMMAND_ID=$(aws ssm send-command \
            --targets "Key=tag:Name,Values=<EC2_TAG_NAME>" \
            --document-name "AWS-RunShellScript" \
            --parameters commands="[
              \"echo $COMPOSE_B64 | base64 -d > /opt/eai/docker-compose.prod.yml\",
              \"DB_PASS=\$(aws ssm get-parameter --name /eai-project/rds/master_password --with-decryption --query Parameter.Value --output text --region ${{ env.AWS_REGION }})\",
              \"API_TOKEN=\$(aws ssm get-parameter --name /eai-project/api/security_token --with-decryption --query Parameter.Value --output text --region ${{ env.AWS_REGION }})\",
              \"echo DATABASE_URL=postgresql+psycopg://smart_meter_admin:\$DB_PASS@${{ vars.RDS_ENDPOINT }}:5432/smart_meter_warehouse > /opt/eai/.env\",
              \"echo API_SECURITY_TOKEN=\$API_TOKEN >> /opt/eai/.env\",
              \"aws ecr get-login-password --region ${{ env.AWS_REGION }} | docker login --username AWS --password-stdin ${{ env.ECR_REGISTRY }}\",
              \"cd /opt/eai && ECR_REGISTRY=${{ env.ECR_REGISTRY }} IMAGE_TAG=${{ github.sha }} docker-compose -f docker-compose.prod.yml --env-file .env pull\",
              \"cd /opt/eai && ECR_REGISTRY=${{ env.ECR_REGISTRY }} IMAGE_TAG=${{ github.sha }} docker-compose -f docker-compose.prod.yml --env-file .env up -d\"
            ]" \
            --query "Command.CommandId" --output text)

          for i in $(seq 1 20); do
            STATUS=$(aws ssm get-command-invocation \
              --command-id "$COMMAND_ID" \
              --instance-id $(aws ec2 describe-instances --filters "Name=tag:Name,Values=<EC2_TAG_NAME>" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text) \
              --query "Status" --output text)
            echo "SSM command status: $STATUS"
            [[ "$STATUS" == "Success" ]] && exit 0
            [[ "$STATUS" == "Failed" || "$STATUS" == "Cancelled" || "$STATUS" == "TimedOut" ]] && exit 1
            sleep 15
          done
          echo "Timed out waiting for deploy command" && exit 1
```

**Repository configuration required (GitHub Settings):**
- Settings → Secrets and variables → Actions → **Variables tab → Repository variables** (not Environment variables — `AWS_ACCOUNT_ID` is read by jobs that run before the `production` environment gate, and Environment-scoped variables are invisible to jobs that don't declare `environment:`): `AWS_ACCOUNT_ID` (see placeholder table), `RDS_ENDPOINT` (retrieved in Phase 2.9 — do not proceed here if that value has not yet been obtained)
- Environments: create `production`, with a required reviewer, to gate the `deploy` job

Commit both new files:

```bash
# Run from: <repo-root>
git add .github/workflows/ci.yml infra/docker-compose.prod.yml
git commit -m "ci: TruffleHog and Trivy scanning, OIDC ECR push, SSM deploy reading secrets from Parameter Store"
git push origin <branch-name>
```
```powershell
# PowerShell equivalent — run from: <repo-root>
git add .github/workflows/ci.yml infra/docker-compose.prod.yml
git commit -m "ci: TruffleHog and Trivy scanning, OIDC ECR push, SSM deploy reading secrets from Parameter Store"
git push origin <branch-name>
```

---

## Phase 4 — Initial Deployment and Verification

```bash
# Run from: <repo-root>
git checkout develop
git merge <feature-branch-name>
git push origin develop

git checkout main
git pull origin main
git merge develop
git push origin main
```
```powershell
# PowerShell equivalent — run from: <repo-root>
git checkout develop
git merge <feature-branch-name>
git push origin develop

git checkout main
git pull origin main
git merge develop
git push origin main
```

Approve the `production` environment gate in the repository's Actions tab when prompted.

**Verification, without SSH:**

```bash
# Run from: anywhere with AWS CLI configured against the target account
aws ssm start-session --target $(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<EC2_TAG_NAME>" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
docker compose -f /opt/eai/docker-compose.prod.yml ps
exit

# Run from: <repo-root>/infra
cd infra
API_URL=$(terraform output -raw api_gateway_url)
curl $API_URL/health
```
```powershell
# PowerShell equivalent
$instanceId = aws ec2 describe-instances --filters "Name=tag:Name,Values=<EC2_TAG_NAME>" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text
aws ssm start-session --target $instanceId
# Inside the session: docker compose -f /opt/eai/docker-compose.prod.yml ps
exit

cd infra
$apiUrl = terraform output -raw api_gateway_url
Invoke-RestMethod -Uri "$apiUrl/health"
```

**Expected result:** the `docker compose ps` output shows both services as `running`; the `curl`/`Invoke-RestMethod` call against the API Gateway URL returns `{"status":"UP"}`.
