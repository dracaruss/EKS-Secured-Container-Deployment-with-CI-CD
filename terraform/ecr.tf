resource "aws_ecr_repository" "osticket" {
  name                 = "osticket"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Project = "osticket-eks"
  }
}

resource "aws_ecr_repository" "mysql" {
  name                 = "osticket-mysql"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Project = "osticket-eks"
  }
}

resource "aws_ecr_lifecycle_policy" "osticket" {
  repository = aws_ecr_repository.osticket.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
