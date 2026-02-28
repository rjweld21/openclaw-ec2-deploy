# Resource Management Best Practices
# Add these patterns to your main.tf for idempotent deployments

# 1. Use lifecycle rules to prevent resource conflicts
resource "aws_cloudwatch_log_group" "openclaw_logs" {
  name = "/aws/ec2/openclaw-${var.environment}"
  
  lifecycle {
    # Prevent destruction of log groups with data
    prevent_destroy = true
    
    # Ignore changes to retention if set manually
    ignore_changes = [retention_in_days]
  }
  
  # Handle existing resources gracefully
  tags = merge(local.common_tags, {
    Name = "openclaw-${var.environment}-logs"
  })
}

# 2. Use data sources for existing resources when possible
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  
  tags = {
    Name = "openclaw-${var.environment}-vpc"
  }
}

resource "aws_vpc" "openclaw_vpc" {
  count = var.use_existing_vpc ? 0 : 1
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "openclaw-${var.environment}-vpc"
  })
}

# 3. Use locals for flexible resource references
locals {
  vpc_id = var.use_existing_vpc ? data.aws_vpc.existing[0].id : aws_vpc.openclaw_vpc[0].id
}

# 4. Add variables for flexibility
variable "use_existing_vpc" {
  description = "Use existing VPC instead of creating new one"
  type        = bool
  default     = false
}

# 5. Import blocks removed - will create resources fresh
# If you need to import existing resources, use: terraform import aws_cloudwatch_log_group.openclaw_logs /actual/log/group/name