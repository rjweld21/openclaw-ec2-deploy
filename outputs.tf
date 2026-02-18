# Output values for OpenClaw EC2 deployment
# Addresses output reference errors and provides debugging information

# VPC Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "availability_zones" {
  description = "Availability zones used"
  value       = local.validated_azs
}

# Subnet Information
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# Security Group Information
output "app_security_group_id" {
  description = "ID of the application security group"
  value       = aws_security_group.app.id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = var.enable_load_balancer ? aws_security_group.alb[0].id : null
}

# Load Balancer Information
output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = var.enable_load_balancer ? aws_lb.app[0].dns_name : null
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = var.enable_load_balancer ? aws_lb.app[0].zone_id : null
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = var.enable_load_balancer ? aws_lb.app[0].arn : null
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = var.enable_load_balancer ? aws_lb_target_group.app[0].arn : null
}

# Auto Scaling Group Information
output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.app.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.app.latest_version
}

# Application Access Information
output "application_url" {
  description = "URL to access the OpenClaw application"
  value = var.enable_load_balancer ? (
    var.ssl_certificate_arn != "" ? 
    "https://${aws_lb.app[0].dns_name}" : 
    "http://${aws_lb.app[0].dns_name}"
  ) : "Load balancer disabled - access via individual instance IPs"
}

output "health_check_url" {
  description = "URL for application health check"
  value = var.enable_load_balancer ? (
    var.ssl_certificate_arn != "" ?
    "https://${aws_lb.app[0].dns_name}/health" :
    "http://${aws_lb.app[0].dns_name}/health"
  ) : null
}

# IAM Information
output "instance_role_arn" {
  description = "ARN of the EC2 instance role"
  value       = aws_iam_role.app.arn
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = aws_iam_instance_profile.app.name
}

# Monitoring Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.app[0].name : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.enable_cloudwatch_monitoring ? aws_sns_topic.asg_notifications[0].arn : null
}

# Backend State Information
output "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  value       = var.create_state_bucket ? aws_s3_bucket.terraform_state[0].id : "State bucket not created by this configuration"
}

output "terraform_state_dynamodb_table" {
  description = "DynamoDB table for Terraform state locking"
  value       = var.create_state_bucket ? aws_dynamodb_table.terraform_locks[0].name : "State lock table not created by this configuration"
}

# Resource Counts and Limits
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_count              = 1
    subnet_count          = length(aws_subnet.public) + length(aws_subnet.private)
    security_group_count  = var.enable_load_balancer ? 2 : 1
    load_balancer_count   = var.enable_load_balancer ? 1 : 0
    nat_gateway_count     = length(aws_nat_gateway.main)
    eip_count            = length(aws_eip.nat)
    launch_template_count = 1
    autoscaling_group_count = 1
  }
}

# Debugging Information
output "debug_info" {
  description = "Debug information for troubleshooting"
  value = {
    aws_region           = data.aws_region.current.name
    aws_account_id       = data.aws_caller_identity.current.account_id
    selected_ami_id      = var.ami_id != "" ? var.ami_id : try(data.aws_ami.amazon_linux[0].id, "not-found")
    instance_type        = var.instance_type
    key_pair_name        = var.key_pair_name
    vpc_cidr             = var.vpc_cidr
    availability_zones   = local.validated_azs
    project_name         = var.project_name
    environment          = var.environment
    enable_load_balancer = var.enable_load_balancer
    enable_monitoring    = var.enable_cloudwatch_monitoring
  }
}

# Connection Information for SSH (if key pair is configured)
output "ssh_connection_info" {
  description = "SSH connection information"
  value = var.key_pair_name != "" ? {
    note = "SSH access is configured through the bastion host pattern or Session Manager"
    key_pair = var.key_pair_name
    security_group = aws_security_group.app.id
    suggestion = "Use AWS Session Manager for secure access: aws ssm start-session --target <instance-id>"
  } : {
    note = "No SSH key pair configured - use AWS Session Manager for access"
    suggestion = "aws ssm start-session --target <instance-id>"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs (approximate)"
  value = {
    note = "These are rough estimates - actual costs may vary"
    ec2_instances = "~$${var.desired_capacity * 50}/month for ${var.desired_capacity} x ${var.instance_type} instances"
    load_balancer = var.enable_load_balancer ? "~$16.20/month for ALB" : "No load balancer"
    nat_gateways = "~$${length(local.validated_azs) * 32}/month for ${length(local.validated_azs)} NAT gateways"
    data_transfer = "Variable based on usage"
    monitoring = var.enable_cloudwatch_monitoring ? "Variable based on metrics and logs" : "Basic monitoring only"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Wait for Auto Scaling Group to launch instances (~5-10 minutes)",
    "2. Check application health at: ${var.enable_load_balancer ? (var.ssl_certificate_arn != "" ? "https" : "http") : "http"}://${var.enable_load_balancer ? aws_lb.app[0].dns_name : "<instance-ip>"}${var.enable_load_balancer ? "/health" : ":${var.openclaw_port}/health"}",
    "3. Monitor CloudWatch metrics and logs if enabled",
    "4. Configure DNS records to point to the load balancer if needed",
    "5. Set up backup and monitoring alerts as required",
    "6. Review security groups and access controls",
    "7. Consider setting up AWS WAF for additional protection"
  ]
}