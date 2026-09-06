resource "aws_subnet" "subnet-2" {
  vpc_id            = aws_vpc.enterprise_network.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"

  tags = { Name = "Primary-Subnet-2", Environment = "Production" }
}
