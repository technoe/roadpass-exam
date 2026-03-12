variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. staging, production)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.16.0.0/16"
}

variable "azs" {
  description = "List of availability zones (exactly 2)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) == 2
    error_message = "Exactly 2 availability zones must be provided."
  }
}

variable "public_subnet_cidrs" {
  description = "List of 4 CIDR blocks for public subnets (2 per AZ)"
  type        = list(string)
  default = [
    "172.16.0.0/20",
    "172.16.16.0/20",
    "172.16.32.0/20",
    "172.16.48.0/20",
  ]

  validation {
    condition     = length(var.public_subnet_cidrs) == 4
    error_message = "Exactly 4 public subnet CIDRs must be provided (2 per AZ)."
  }
}

variable "private_subnet_cidrs" {
  description = "List of 4 CIDR blocks for private subnets (2 per AZ)"
  type        = list(string)
  default = [
    "172.16.64.0/20",
    "172.16.80.0/20",
    "172.16.96.0/20",
    "172.16.112.0/20",
  ]

  validation {
    condition     = length(var.private_subnet_cidrs) == 4
    error_message = "Exactly 4 private subnet CIDRs must be provided (2 per AZ)."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
