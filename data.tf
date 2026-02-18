# Data sources for resource discovery and validation
# Addresses AMI availability, AZ distribution, and resource limits

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
  
  # Filter out zones with limited instance type availability
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Local values for computed configurations
locals {
  # Use provided AZs or auto-discover
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  
  # Ensure we have at least 2 AZs for load balancer
  validated_azs = length(local.availability_zones) >= 2 ? local.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)
  
  # Common tags
  common_tags = merge({
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Region      = data.aws_region.current.name
    Account     = data.aws_caller_identity.current.account_id
  }, var.additional_tags)
}

# Get latest Amazon Linux 2 AMI if not specified
data "aws_ami" "amazon_linux" {
  count       = var.ami_id == "" ? 1 : 0
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

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Validate AMI exists in current region if specified
data "aws_ami" "specified" {
  count  = var.ami_id != "" ? 1 : 0
  owners = ["self", "amazon", "aws-marketplace"]

  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}

# Check for existing VPCs to avoid CIDR conflicts
data "aws_vpcs" "existing" {
  filter {
    name   = "cidr"
    values = [var.vpc_cidr]
  }
}

# Check EC2 service limits (this requires appropriate IAM permissions)
data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

# Get default VPC to understand existing network setup
data "aws_vpc" "default" {
  default = true
}

# Check for existing key pairs
data "aws_key_pair" "selected" {
  count    = var.key_pair_name != "" ? 1 : 0
  key_name = var.key_pair_name
}

# Validate instance type availability in selected AZs
data "aws_ec2_instance_type_offerings" "available" {
  for_each = toset(local.validated_azs)
  
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
  
  filter {
    name   = "location"
    values = [each.value]
  }
  
  location_type = "availability-zone"
}

# Check current resource counts to avoid limits
data "aws_vpcs" "all" {}

data "aws_internet_gateways" "all" {}

# Output validation results for debugging
output "validation_results" {
  description = "Validation results for debugging"
  value = {
    region                = data.aws_region.current.name
    account_id           = data.aws_caller_identity.current.account_id
    selected_ami         = var.ami_id != "" ? var.ami_id : try(data.aws_ami.amazon_linux[0].id, "not-found")
    availability_zones   = local.validated_azs
    instance_type_available = {
      for az in local.validated_azs : az => length(data.aws_ec2_instance_type_offerings.available[az].instance_types) > 0
    }
    vpc_cidr_conflicts   = length(data.aws_vpcs.existing.ids) > 0 ? data.aws_vpcs.existing.ids : []
    existing_vpc_count   = length(data.aws_vpcs.all.ids)
    key_pair_exists     = var.key_pair_name != "" ? length(data.aws_key_pair.selected) > 0 : false
  }
}

# Validation checks - these will cause terraform plan to fail with helpful messages
check "ami_availability" {
  assert {
    condition = var.ami_id != "" ? length(data.aws_ami.specified) > 0 : length(data.aws_ami.amazon_linux) > 0
    error_message = var.ami_id != "" ? 
      "Specified AMI ${var.ami_id} is not available in region ${data.aws_region.current.name}" :
      "No suitable Amazon Linux 2 AMI found in region ${data.aws_region.current.name}"
  }
}

check "availability_zones" {
  assert {
    condition     = length(local.validated_azs) >= 2
    error_message = "At least 2 availability zones are required for load balancer setup. Available AZs: ${join(", ", data.aws_availability_zones.available.names)}"
  }
}

check "instance_type_availability" {
  assert {
    condition = alltrue([
      for az in local.validated_azs : length(data.aws_ec2_instance_type_offerings.available[az].instance_types) > 0
    ])
    error_message = "Instance type ${var.instance_type} is not available in all selected availability zones: ${join(", ", local.validated_azs)}"
  }
}

check "vpc_limit" {
  assert {
    condition     = length(data.aws_vpcs.all.ids) < 5  # AWS default VPC limit
    error_message = "VPC limit approaching. Current VPCs: ${length(data.aws_vpcs.all.ids)}/5. Consider cleaning up unused VPCs or request limit increase."
  }
}

check "vpc_cidr_conflict" {
  assert {
    condition     = length(data.aws_vpcs.existing.ids) == 0
    error_message = "VPC with CIDR ${var.vpc_cidr} already exists. Choose a different CIDR block or use existing VPC."
  }
}

check "key_pair_validation" {
  assert {
    condition     = var.key_pair_name == "" || length(data.aws_key_pair.selected) > 0
    error_message = "Key pair '${var.key_pair_name}' does not exist in region ${data.aws_region.current.name}. Create it or use a different key pair name."
  }
}