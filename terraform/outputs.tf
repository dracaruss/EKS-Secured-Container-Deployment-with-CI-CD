output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for osTicket"
  value       = aws_ecr_repository.osticket.repository_url
}

output "ecr_mysql_repository_url" {
  description = "ECR repository URL for MySQL"
  value       = aws_ecr_repository.mysql.repository_url
}
