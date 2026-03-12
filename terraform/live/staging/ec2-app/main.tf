terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Pull VPC outputs from the staging/vpc state
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "staging/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  public_subnet_ids  = data.terraform_remote_state.vpc.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  vpc_cidr           = data.terraform_remote_state.vpc.outputs.vpc_cidr_block
}

# ──────────────────────────────────────────────────────────────
# IAM — EC2 Instance Role
# ──────────────────────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# SSM access: allows Session Manager without SSH or a bastion host.
# This is the recommended approach — no key management, full audit trail in CloudTrail.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped S3 read policy — example of least-privilege inline policy.
# Adjust the bucket ARN to match any assets bucket the app needs.
resource "aws_iam_role_policy" "s3_read" {
  name = "${var.name}-ec2-s3-read"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = ["arn:aws:s3:::${var.app_assets_bucket}", "arn:aws:s3:::${var.app_assets_bucket}/*"]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Security Groups
# ──────────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Allow HTTP inbound to the ALB"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-sg-alb" })
}

resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2"
  description = "Allow HTTP from ALB; restrict SSH to management CIDR"
  vpc_id      = local.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # SSH is scoped to management CIDR. With SSM Session Manager attached,
  # port 22 can be removed entirely in a hardened environment.
  ingress {
    description = "SSH from management CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.management_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-sg-ec2" })
}

# ──────────────────────────────────────────────────────────────
# Launch Template
# ──────────────────────────────────────────────────────────────
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
  }

  # Fry role variables injected as userdata.
  # cloud-init runs /var/lib/cloud/scripts/per-boot/fry.sh on each boot.
  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    server_name = var.server_name
    environment = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-instance" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-volume" })
  }

  tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Application Load Balancer
# ──────────────────────────────────────────────────────────────
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_lb_target_group" "this" {
  name     = "${var.name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# ──────────────────────────────────────────────────────────────
# Auto Scaling Group
# ──────────────────────────────────────────────────────────────
resource "aws_autoscaling_group" "this" {
  name                = "${var.name}-asg"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 4
  vpc_zone_identifier = local.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.this.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-asg-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
