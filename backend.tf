# Backend configuration for Terraform state
# Keep it simple for initial deployment - we'll use local state for now

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# We'll use local state for simplicity
# In production, you can configure S3 backend later