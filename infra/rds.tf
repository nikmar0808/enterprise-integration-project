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
  value = "EAI-SECRET-SECURE-KEY-2026"
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
    from_port = 0
    to_port = 0
    protocol = "-1"
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
