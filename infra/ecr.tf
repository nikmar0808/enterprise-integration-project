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
