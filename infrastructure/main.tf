# OpenClaw EC2 Deployment - Terraform Infrastructure
# Production-ready setup with security, monitoring, and cost optimization

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for OpenClaw Gateway"
  type        = string
  default     = "t3.small"  # Cost-optimized for moderate OpenClaw usage
}

variable "domain_name" {
  description = "Domain name for OpenClaw (optional, for SSL)"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "AWS Key Pair name for SSH access"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production!
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC and Networking
resource "aws_vpc" "openclaw_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "openclaw-vpc"
  }
}

resource "aws_internet_gateway" "openclaw_igw" {
  vpc_id = aws_vpc.openclaw_vpc.id

  tags = {
    Name = "openclaw-igw"
  }
}

resource "aws_route_table" "openclaw_public_rt" {
  vpc_id = aws_vpc.openclaw_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.openclaw_igw.id
  }

  tags = {
    Name = "openclaw-public-rt"
  }
}

resource "aws_subnet" "openclaw_public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.openclaw_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "openclaw-public-subnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "openclaw_public_rta" {
  count          = 2
  subnet_id      = aws_subnet.openclaw_public_subnet[count.index].id
  route_table_id = aws_route_table.openclaw_public_rt.id
}

# Security Groups
resource "aws_security_group" "openclaw_ec2_sg" {
  name        = "openclaw-ec2-sg"
  description = "Security group for OpenClaw EC2 instance"
  vpc_id      = aws_vpc.openclaw_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # HTTP from ALB only
  ingress {
    from_port       = 18789
    to_port         = 18789
    protocol        = "tcp"
    security_groups = [aws_security_group.openclaw_alb_sg.id]
    description     = "OpenClaw Gateway from ALB"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "openclaw-ec2-sg"
  }
}

resource "aws_security_group" "openclaw_alb_sg" {
  name        = "openclaw-alb-sg"
  description = "Security group for OpenClaw Application Load Balancer"
  vpc_id      = aws_vpc.openclaw_vpc.id

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # HTTP access (redirect to HTTPS)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access (redirect to HTTPS)"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "openclaw-alb-sg"
  }
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "openclaw_ec2_role" {
  name = "openclaw-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "openclaw_ec2_policy" {
  name = "openclaw-ec2-policy"
  role = aws_iam_role.openclaw_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "openclaw_ec2_profile" {
  name = "openclaw-ec2-profile"
  role = aws_iam_role.openclaw_ec2_role.name
}

# Application Load Balancer
resource "aws_lb" "openclaw_alb" {
  name               = "openclaw-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.openclaw_alb_sg.id]
  subnets           = aws_subnet.openclaw_public_subnet[*].id

  enable_deletion_protection = false

  tags = {
    Name = "openclaw-alb"
  }
}

resource "aws_lb_target_group" "openclaw_tg" {
  name     = "openclaw-tg"
  port     = 18789
  protocol = "HTTP"
  vpc_id   = aws_vpc.openclaw_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "openclaw-tg"
  }
}

# SSL Certificate (if domain provided)
resource "aws_acm_certificate" "openclaw_cert" {
  count           = var.domain_name != "" ? 1 : 0
  domain_name     = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "openclaw-cert"
  }
}

# ALB Listeners
resource "aws_lb_listener" "openclaw_https" {
  count             = var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.openclaw_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.openclaw_cert[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.openclaw_tg.arn
  }
}

resource "aws_lb_listener" "openclaw_http" {
  load_balancer_arn = aws_lb.openclaw_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = var.domain_name != "" ? "redirect" : "forward"
    
    dynamic "redirect" {
      for_each = var.domain_name != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.domain_name == "" ? [1] : []
      content {
        target_group_arn = aws_lb_target_group.openclaw_tg.arn
      }
    }
  }
}

# Launch Template
resource "aws_launch_template" "openclaw_template" {
  name_prefix   = "openclaw-template"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [aws_security_group.openclaw_ec2_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.openclaw_ec2_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    aws_region = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "openclaw-gateway"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "openclaw_asg" {
  name                = "openclaw-asg"
  vpc_zone_identifier = aws_subnet.openclaw_public_subnet[*].id
  target_group_arns   = [aws_lb_target_group.openclaw_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.openclaw_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "openclaw-asg"
    propagate_at_launch = false
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "openclaw-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.openclaw_asg.name
  }
}

# Outputs
output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.openclaw_alb.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.openclaw_alb.zone_id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.openclaw_vpc.id
}