# Infrastructure

Infrastructure-as-Code for OpenClaw EC2 deployment.

## Contents
- `terraform/` - Terraform configurations for AWS resources
- `cloudformation/` - Alternative CloudFormation templates
- `security/` - Security groups, IAM roles, SSL configs

## Resources to Deploy
- EC2 instances with optimized sizing
- Application Load Balancer with SSL
- Security groups (restrictive by default)
- IAM roles with minimal permissions
- CloudWatch monitoring and alarms
- Route 53 DNS (optional)

## Usage
TBD - Will be automated via GitHub Actions