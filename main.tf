# OpenClaw EC2 Deployment - Main Infrastructure
# Clean main file - all resources are defined in modular files

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = merge(var.additional_tags, {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    })
  }
}

# Data sources for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Local values for common tags
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}