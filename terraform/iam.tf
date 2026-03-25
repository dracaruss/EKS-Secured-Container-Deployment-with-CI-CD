# ─────────────────────────────────────────────────────────────
# OIDC Provider for GitHub Actions
# This lets GitHub Actions authenticate to AWS without storing
# long-lived credentials as GitHub secrets. GitHub signs a JWT
# token, AWS verifies it against this provider, and grants
# temporary credentials scoped to the role below.
# ─────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Project = "osticket-eks"
  }
}

# ─────────────────────────────────────────────────────────────
# IAM Role for GitHub Actions
# The trust policy restricts assumption to your specific repo
# and only the main branch. Replace YOUR_GITHUB_USERNAME and
# YOUR_REPO_NAME with your actual values.
# ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "github_actions" {
  name = "github-actions-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:dracaruss/EKS-Secured-Container-Deployment-with-CI-CD:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Project = "osticket-eks"
  }
}

# ─────────────────────────────────────────────────────────────
# ECR Permissions
# Push and pull images, read scan results
# ─────────────────────────────────────────────────────────────

resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "github-actions-ecr-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImageScanFindings"
        ]
        Resource = [
          aws_ecr_repository.osticket.arn,
          aws_ecr_repository.mysql.arn
        ]
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# EKS Permissions
# Update kubeconfig and interact with the cluster
# ─────────────────────────────────────────────────────────────

resource "aws_iam_role_policy" "github_actions_eks" {
  name = "github-actions-eks-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = module.eks.cluster_arn
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# EKS Access Entry for GitHub Actions
# Grants the GitHub Actions role permission to deploy
# workloads into the cluster. Without this, the role can
# describe the cluster but kubectl commands will be denied.
# ─────────────────────────────────────────────────────────────

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"

  tags = {
    Project = "osticket-eks"
  }
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
