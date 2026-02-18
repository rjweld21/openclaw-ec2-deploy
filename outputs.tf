# Outputs for OpenClaw EC2 Deployment

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "security_group_ec2_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.ec2.id
}

output "security_group_alb_id" {
  description = "ID of the ALB security group"
  value       = var.enable_load_balancer ? aws_security_group.alb[0].id : null
}

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = var.enable_load_balancer ? aws_lb.app[0].arn : null
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = var.enable_load_balancer ? aws_lb.app[0].dns_name : null
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = var.enable_load_balancer ? aws_lb.app[0].zone_id : null
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = var.enable_load_balancer ? aws_lb_target_group.app[0].arn : null
}

output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "auto_scaling_group_arn" {
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

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.app[0].name : null
}

# Application URLs
output "application_url" {
  description = "URL to access the OpenClaw application"
  value = var.enable_load_balancer ? (
    var.ssl_certificate_arn != "" ? 
    "https://${aws_lb.app[0].dns_name}" : 
    "http://${aws_lb.app[0].dns_name}"
  ) : "http://[EC2_PUBLIC_IP]:${var.openclaw_port}"
}

output "health_check_url" {
  description = "URL for health check endpoint"
  value = var.enable_load_balancer ? (
    var.ssl_certificate_arn != "" ? 
    "https://${aws_lb.app[0].dns_name}/health" : 
    "http://${aws_lb.app[0].dns_name}/health"
  ) : "http://[EC2_PUBLIC_IP]:${var.openclaw_port}/health"
}

# Frontend Infrastructure Outputs
output "frontend_s3_bucket_name" {
  description = "Name of the S3 bucket hosting the frontend"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_s3_bucket_arn" {
  description = "ARN of the S3 bucket hosting the frontend"
  value       = aws_s3_bucket.frontend.arn
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_artifacts_bucket_name" {
  description = "Name of the S3 bucket for frontend build artifacts"
  value       = aws_s3_bucket.frontend_artifacts.id
}

# Updated Application URLs with CloudFront
output "frontend_url" {
  description = "URL to access the React frontend via CloudFront"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "api_url" {
  description = "URL to access the API via CloudFront"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}/api"
}

# Deployment Information
output "deployment_info" {
  description = "Key deployment information"
  value = {
    environment            = var.environment
    region                = var.aws_region
    instance_type         = var.instance_type
    min_instances         = var.min_size
    max_instances         = var.max_size
    desired_instances     = var.desired_capacity
    load_balancer_enabled = var.enable_load_balancer
    monitoring_enabled    = var.enable_cloudwatch_monitoring
    openclaw_version      = var.openclaw_version
    openclaw_port         = var.openclaw_port
    frontend_enabled      = true
    cloudfront_enabled    = true
  }
}