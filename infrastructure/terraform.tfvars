# OpenClaw EC2 Deployment Configuration
# This file provides default values for the deployment

# AWS Configuration
aws_region = "us-east-1"

# EC2 Configuration  
instance_type = "t3.small"
key_pair_name = "openclaw-deploy-key"

# Security Configuration
allowed_ssh_cidrs = ["0.0.0.0/0"]  # Update this to your IP for security

# Optional: Domain Configuration (leave empty for no SSL)
domain_name = ""