# OpenClaw EC2 Deployment - Main Infrastructure
# Clean main file - all resources, data sources, and locals are defined in modular files

provider "aws" {
  region = var.aws_region
  
  # Enhanced configuration to prevent plugin timeouts and API issues
  max_retries         = 3
  skip_region_validation = false
  skip_credentials_validation = false
  skip_metadata_api_check = false
  
  default_tags {
    tags = merge(var.additional_tags, {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      TerraformVersion = "1.6.6"
    })
  }
}