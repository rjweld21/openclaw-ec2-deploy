# OpenClaw EC2 Deployment - Main Infrastructure
# Clean main file - all resources, data sources, and locals are defined in modular files

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