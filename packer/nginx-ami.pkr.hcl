packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# ──────────────────────────────────────────────────────────────
# Variables
# ──────────────────────────────────────────────────────────────
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "environment" {
  type    = string
  default = "staging"
}

# ──────────────────────────────────────────────────────────────
# Source — Amazon Linux 2023
# ──────────────────────────────────────────────────────────────
source "amazon-ebs" "nginx" {
  region        = var.region
  instance_type = var.instance_type

  # Always resolve the latest AL2023 AMI at build time
  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["137112412989"] # Amazon's official account ID
    most_recent = true
  }

  ssh_username = "ec2-user"
  ami_name     = "roadpass-nginx-${var.environment}-{{timestamp}}"
  ami_description = "nginx on Amazon Linux 2023 — built by Packer/Ansible (pack phase)"

  tags = {
    Name        = "roadpass-nginx-${var.environment}"
    BuiltBy     = "packer"
    Environment = var.environment
    Project     = "roadpass-exam"
    OS          = "Amazon Linux 2023"
  }

  # Snapshot tags propagated to all AMI snapshots
  snapshot_tags = {
    Name    = "roadpass-nginx-${var.environment}"
    BuiltBy = "packer"
  }
}

# ──────────────────────────────────────────────────────────────
# Build — pack phase only
# The fry phase runs at instance launch time via EC2 userdata.
# ──────────────────────────────────────────────────────────────
build {
  name    = "nginx-pack"
  sources = ["source.amazon-ebs.nginx"]

  # Pack phase: install nginx and bake the static page into the AMI
  provisioner "ansible" {
    playbook_file = "${path.root}/ansible/playbook-pack.yml"
    user          = "ec2-user"
    extra_arguments = [
      "--extra-vars", "environment=${var.environment}",
    ]
  }
}
