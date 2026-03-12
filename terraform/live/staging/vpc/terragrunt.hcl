include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../..//modules/vpc"
}

inputs = {
  name        = "roadpass-staging"
  environment = "staging"
  vpc_cidr    = "172.16.0.0/16"

  azs = ["us-east-1a", "us-east-1b"]

  # 2 public subnets per AZ → 4 total
  public_subnet_cidrs = [
    "172.16.0.0/20",  # us-east-1a public-1
    "172.16.16.0/20", # us-east-1a public-2
    "172.16.32.0/20", # us-east-1b public-1
    "172.16.48.0/20", # us-east-1b public-2
  ]

  # 2 private subnets per AZ → 4 total
  private_subnet_cidrs = [
    "172.16.64.0/20",  # us-east-1a private-1
    "172.16.80.0/20",  # us-east-1a private-2
    "172.16.96.0/20",  # us-east-1b private-1
    "172.16.112.0/20", # us-east-1b private-2
  ]
}
