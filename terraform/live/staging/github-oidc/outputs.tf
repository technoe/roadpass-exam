output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions — set this as AWS_ROLE_ARN in the workflow or hardcode it"
  value       = aws_iam_role.github_oidc_eks.arn
}
