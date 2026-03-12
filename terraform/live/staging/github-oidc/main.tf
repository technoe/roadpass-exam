terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ──────────────────────────────────────────────────────────────
# GitHub OIDC Provider
#
# Allows GitHub Actions to exchange a signed JWT for temporary
# AWS credentials via sts:AssumeRoleWithWebIdentity — no stored
# secrets anywhere.
# ──────────────────────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # SHA-1 thumbprint of the GitHub OIDC TLS certificate root CA.
  # This value is stable; see: https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(var.tags, { Name = "github-oidc" })
}

# ──────────────────────────────────────────────────────────────
# IAM Role — trusted by GitHub Actions on main branch only
# ──────────────────────────────────────────────────────────────
resource "aws_iam_role" "github_oidc_eks" {
  name        = "github-oidc-eks-deploy"
  description = "Assumed by GitHub Actions via OIDC to deploy to staging EKS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Only allow the sts.amazonaws.com audience (set by configure-aws-credentials action)
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Wildcard scoped to this repo only.
          # When a job declares `environment:`, GitHub's sub claim becomes
          # "repo:org/repo:environment:name" instead of "repo:org/repo:ref:refs/heads/main".
          # The wildcard covers both push-triggered and environment-scoped jobs
          # while still preventing any other repo from assuming this role.
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "github-oidc-eks-deploy" })
}

# ──────────────────────────────────────────────────────────────
# IAM Policy — minimal permissions
#
# sts:GetCallerIdentity — lets the workflow verify auth succeeded
# eks:DescribeCluster   — lets aws cli generate a kubeconfig
# eks:AccessKubernetesApi — lets helm/kubectl talk to the cluster
#
# Forward-looking: EKS permissions are harmless now (no cluster),
# but ready when the cluster is created.
# ──────────────────────────────────────────────────────────────
resource "aws_iam_role_policy" "github_oidc_eks" {
  name = "github-oidc-eks-deploy-policy"
  role = aws_iam_role.github_oidc_eks.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "VerifyAuth"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:AccessKubernetesApi",
        ]
        # Scoped to staging cluster only — no wildcard
        Resource = "arn:aws:eks:us-east-1:${data.aws_caller_identity.current.account_id}:cluster/staging-cluster"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
