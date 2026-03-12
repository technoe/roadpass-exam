variable "name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "roadpass-staging"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "ami_id" {
  description = "ID of the AMI built by Packer (nginx-ami)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "server_name" {
  description = "Nginx server_name value injected via userdata (fry role)"
  type        = string
  default     = "staging.roadpass-exam.internal"
}

variable "management_cidr" {
  description = "CIDR block allowed SSH access to EC2 instances. Set to your bastion/office IP."
  type        = string
  default     = "10.0.0.0/8"
}

variable "app_assets_bucket" {
  description = "S3 bucket name the EC2 instances are allowed to read from"
  type        = string
  default     = "roadpass-exam-assets"
}

variable "tfstate_bucket" {
  description = "S3 bucket name used for remote state (to read VPC outputs)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
