# Terraform and Provider Version Constraints
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Backend configuration will be provided via CLI arguments in GitHub Actions
    # This allows for environment-specific state management:
    #   Dev: bucket/openclaw-ec2/dev/terraform.tfstate
    #   Staging: bucket/openclaw-ec2/staging/terraform.tfstate
    #   Prod: bucket/openclaw-ec2/prod/terraform.tfstate
    #
    # Configuration provided via terraform init:
    # -backend-config="bucket=${TF_STATE_BUCKET}"
    # -backend-config="key=openclaw-ec2/${ENVIRONMENT}/terraform.tfstate"  
    # -backend-config="region=${AWS_REGION}"
    # -backend-config="dynamodb_table=${TF_STATE_LOCK_TABLE}"
  }
}