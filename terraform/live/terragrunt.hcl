# ──────────────────────────────────────────────────────────────
# Root Terragrunt configuration
# All child configs include this via include "root".
# ──────────────────────────────────────────────────────────────

locals {
  # Update this with the output of `terraform output tfstate_bucket_name`
  # after running bootstrap/ for the first time.
  tfstate_bucket     = "roadpass-exam-tfstate-585445411780"
  tfstate_lock_table = "roadpass-exam-tfstate-lock"
  aws_region         = "us-east-1"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = local.tfstate_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.tfstate_lock_table
    encrypt        = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
  default_tags {
    tags = {
      Environment = "staging"
      Project     = "roadpass-exam"
      Owner       = "mike-noe"
      ManagedBy   = "terraform"
      CostCenter  = "engineering"
    }
  }
}
EOF
}

# Common inputs propagated to all child modules
inputs = {
  tags = {
    Environment = "staging"
    Project     = "roadpass-exam"
    Owner       = "mike-noe"
    ManagedBy   = "terraform"
    CostCenter  = "engineering"
  }
}
