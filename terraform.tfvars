# Terraform variables for OpenClaw EC2 Deployment

# AWS Configuration
aws_region = "us-east-1"
environment = "dev"

# Project Configuration
project_name = "openclaw"

# Instance Configuration
instance_type = "t3.small"  # Start with t3.small for testing
key_pair_name = "openclaw-key"

# Auto Scaling Configuration
min_size = 1
max_size = 2
desired_capacity = 1

# Network Configuration
vpc_cidr = "10.0.0.0/16"
allowed_cidr_blocks = ["0.0.0.0/0"]

# Feature Configuration
enable_load_balancer = true
enable_cloudwatch_monitoring = true

# OpenClaw Configuration
openclaw_version = "latest"
openclaw_port = 8080  # Updated to match existing security group

# Anthropic API Key - Your local key
anthropic_api_key = "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"

# Additional Tags
additional_tags = {
  "Owner"      = "rjw"
  "Purpose"    = "openclaw-gateway"
  "DeployedBy" = "terraform"
}