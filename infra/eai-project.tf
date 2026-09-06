# Provider Name as per registry.terraform.io
# aws hashicorp/aws 6.x
# format provider "provider_name" { ... }
provider "aws" {
  region = "ap-south-1"
  # Credentials supplied by Terraform Cloud's dynamic provider credentials
  # (OIDC, via tfc-run-role). No profile referencing SSO or Identity Center.
}

# 1. Virtual Private Cloud - VPC Configuration (Secure Enterprise Network Boundary)
# format resource "provider_name_type" "resource_label" { ... }
resource "aws_vpc" "enterprise_network" {
  # As per Classless Inter-Domain Routing rules
  # In a /16 network, the last two blocks of numbers can change from 0 to 255.
  # So private IP range from 10.0.0.0 through 10.0.255.255
  # So total number of IP addresses in a /16 network is 65,536 (2^16)
  # (Note: When configured for an AWS VPC, AWS automatically reserves 5 of these IPs for internal routing, DNS, and management tasks).
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name        = "Primary-Enterprise-VPC"
    Environment = "Production"
    Compliance  = "Strict-Regulated"
  }
}

# 2. Subnet Configuration (Secure Enterprise Network Segmentation)
# format resource "provider_name_type" "resource_label" { ... }
resource "aws_subnet" "subnet-1" {
  # Associate this subnet with the VPC created above
  # format vpc_id = resource.provider_name_type.resource_label.id
  vpc_id            = aws_vpc.enterprise_network.id
  # As per Classless Inter-Domain Routing rules
  # In a /24 network, the last two blocks of numbers can change from 0 to 255.
  # So private IP range from 10.0.1.0 through 10.0.1.255
  # So total number of IP addresses in a /24 network is 256 (2^8)
  cidr_block        = "10.0.1.0/24"

  # NEW: pin this subnet to one specific Availability Zone in Mumbai. Without this,
  # AWS still works, but leaving it implicit makes future resources (if you ever add
  # a second subnet, or an EBS volume) harder to reason about — better to be explicit.
  availability_zone = "ap-south-1a"

  # NEW: this is what actually makes the subnet "public" — instances launched here
  # get a public IP automatically. Without this (and the Internet Gateway + route
  # table below), your EC2 instance would have no way to reach, or be reached from,
  # the internet at all, no matter what security group rules you set.
  map_public_ip_on_launch = true

  tags = {
    Name        = "Primary-Subnet-1"
    Environment = "Production"
    Compliance  = "Strict-Regulated"
  }
}

# 2a. Internet Gateway — NEW.
# Analogy: a VPC with no Internet Gateway is a building with walls and rooms (subnets)
# but no front door. Nothing gets in or out no matter how the rooms are arranged.
resource "aws_internet_gateway" "enterprise_igw" {
  vpc_id = aws_vpc.enterprise_network.id
  tags   = { Name = "Primary-Enterprise-IGW" }
}

# 2b. Route Table — NEW.
# Tells the subnet: "anything not addressed to another machine inside this VPC
# (10.0.0.0/16) should be sent out through the Internet Gateway."
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.enterprise_network.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.enterprise_igw.id
  }

  tags = { Name = "Primary-Public-Route-Table" }
}

# 2c. Route Table Association — NEW.
# The route table above does nothing until it's actually attached to a subnet —
# this is that attachment.
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.public_rt.id
}

# 3. Security Group — NEW.
# Analogy: a bouncer with a strict guest list, not a club with its front door
# propped open. The app port is open to the world 
# since that's the whole point of a service, but nothing else is exposed at all.
resource "aws_security_group" "app_sg" {
  name        = "eai-app-sg"
  description = "Ingestion gateway public; internal service internal-only"
  vpc_id      = aws_vpc.enterprise_network.id

  # Only Port 8081 (ingestion service) opened
  # Port 8082 (transformation service) intentionally not opened.
  ingress {
    description = "Ingestion gateway"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound (Docker image pulls, package updates, AWS API calls)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "eai-app-sg" }
}

# 4. Linux AMI is the standard, lightweight, free-tier-friendly.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# 5. EC2 Instance Configuration (Deploy Compute Resources)
# Placed in VPC/subnet-1 and associated with app_sg for controlling port access
# format resource "provider_name_type" "resource_label" { ... }
resource "aws_instance" "sandbox-1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.subnet-1.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

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

  tags = { Name = "eai-project-host" }
}

output "instance_public_ip" { value = aws_instance.sandbox-1.public_ip }
output "instance_id"        { value = aws_instance.sandbox-1.id }
