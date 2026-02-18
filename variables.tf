# Variables for OpenClaw EC2 Deployment
# Addresses variable validation and type mismatches

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1", "ap-southeast-1"
    ], var.aws_region)
    error_message = "AWS region must be a valid region where OpenClaw is supported."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "openclaw"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "create_state_bucket" {
  description = "Whether to create the Terraform state bucket (set false if already exists)"
  type        = bool
  default     = true
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use (minimum 2 required for load balancer)"
  type        = list(string)
  default     = []  # Will be auto-discovered if empty
  
  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for load balancer setup."
  }
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge", "m5.large", "m5.xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "ami_id" {
  description = "AMI ID to use (leave empty for latest Amazon Linux 2)"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access"
  type        = string
  default     = ""
}

variable "min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_size >= 1 && var.min_size <= 10
    error_message = "Minimum size must be between 1 and 10."
  }
}

variable "max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 3
  
  validation {
    condition     = var.max_size >= 1 && var.max_size <= 20
    error_message = "Maximum size must be between 1 and 20."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.desired_capacity >= 1
    error_message = "Desired capacity must be at least 1."
  }
}

# Load Balancer Configuration
variable "enable_load_balancer" {
  description = "Whether to create an Application Load Balancer"
  type        = bool
  default     = true
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS (leave empty for HTTP only)"
  type        = string
  default     = ""
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the application"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

# OpenClaw Specific Configuration
variable "openclaw_port" {
  description = "Port on which OpenClaw application runs"
  type        = number
  default     = 3000
  
  validation {
    condition     = var.openclaw_port > 0 && var.openclaw_port < 65536
    error_message = "Port must be between 1 and 65535."
  }
}

variable "openclaw_version" {
  description = "OpenClaw version to deploy"
  type        = string
  default     = "latest"
}

# Monitoring Configuration
variable "enable_cloudwatch_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# Backup Configuration
variable "backup_retention_days" {
  description = "Number of days to retain EBS snapshots"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days > 0 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

# Resource Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}