output "tfstate_bucket_name" {
  description = "S3 bucket name for Terraform remote state — use in root terragrunt.hcl"
  value       = aws_s3_bucket.tfstate.bucket
}

output "tfstate_lock_table_name" {
  description = "DynamoDB table name for state locking — use in root terragrunt.hcl"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "aws_account_id" {
  description = "AWS account ID used during bootstrap"
  value       = data.aws_caller_identity.current.account_id
}
