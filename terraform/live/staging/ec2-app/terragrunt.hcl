include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "./"
}

locals {
  root_config = read_terragrunt_config(find_in_parent_folders())
  # Extract the tfstate bucket name from the root remote_state config
  tfstate_bucket = local.root_config.remote_state.config.bucket
}

inputs = {
  name        = "roadpass-staging"
  environment = "staging"

  # Update this after running: cd packer && packer build nginx-ami.pkr.hcl
  ami_id = "ami-REPLACE_WITH_PACKER_OUTPUT"

  instance_type     = "t3.micro"
  server_name       = "staging.roadpass-exam.internal"
  management_cidr   = "10.0.0.0/8"
  app_assets_bucket = "roadpass-exam-assets"
  tfstate_bucket    = local.tfstate_bucket
}
