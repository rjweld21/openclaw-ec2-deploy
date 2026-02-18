# Application Load Balancer configuration
# Addresses load balancer subnet requirements (need 2+ AZs) and SSL certificate handling

# Application Load Balancer
resource "aws_lb" "app" {
  count = var.enable_load_balancer ? 1 : 0

  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets           = aws_subnet.public[*].id

  enable_deletion_protection = false  # Set to true in production

  # Access logs (optional)
  dynamic "access_logs" {
    for_each = var.enable_cloudwatch_monitoring ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = "alb-access-logs"
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-alb"
    Type = "load-balancer"
  })

  # Ensure we have subnets in multiple AZs
  depends_on = [
    aws_subnet.public,
    aws_security_group.alb
  ]
}

# Target Group for application instances
resource "aws_lb_target_group" "app" {
  count = var.enable_load_balancer ? 1 : 0

  name     = "${var.project_name}-${var.environment}-tg"
  port     = var.openclaw_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"  # OpenClaw health check endpoint
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  # Deregistration delay for graceful shutdown
  deregistration_delay = 300

  # Target type
  target_type = "instance"

  # Stickiness (if needed)
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = false
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-target-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# HTTP Listener (redirect to HTTPS if SSL certificate is provided)
resource "aws_lb_listener" "http" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = "80"
  protocol          = "HTTP"

  # If SSL certificate is provided, redirect HTTP to HTTPS
  dynamic "default_action" {
    for_each = var.ssl_certificate_arn != "" ? [1] : []
    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  # If no SSL certificate, forward to target group
  dynamic "default_action" {
    for_each = var.ssl_certificate_arn == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.app[0].arn
    }
  }

  tags = local.common_tags
}

# HTTPS Listener (if SSL certificate is provided)
resource "aws_lb_listener" "https" {
  count = var.enable_load_balancer && var.ssl_certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }

  tags = local.common_tags
}

# Additional listener rules can be added here for path-based routing
resource "aws_lb_listener_rule" "api" {
  count = var.enable_load_balancer ? 1 : 0

  listener_arn = var.ssl_certificate_arn != "" ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  tags = local.common_tags
}

# S3 bucket for ALB access logs (if monitoring is enabled)
resource "aws_s3_bucket" "alb_logs" {
  count = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0

  bucket = "${var.project_name}-${var.environment}-alb-logs-${random_id.alb_logs_suffix[0].hex}"

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-${var.environment}-alb-logs"
    Purpose = "alb-access-logs"
  })
}

resource "random_id" "alb_logs_suffix" {
  count       = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0
  byte_length = 4
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "alb_logs" {
  count  = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count  = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "log_lifecycle"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# S3 bucket policy for ALB logs
resource "aws_s3_bucket_policy" "alb_logs" {
  count  = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main[0].arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs[0].arn}/alb-access-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs[0].arn}/alb-access-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs[0].arn
      }
    ]
  })
}

# Get ELB service account for the region
data "aws_elb_service_account" "main" {
  count = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0
}

# CloudWatch alarms for load balancer
resource "aws_cloudwatch_metric_alarm" "alb_healthy_hosts" {
  count = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-healthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This alarm monitors the number of healthy targets"
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.app[0].arn_suffix
    LoadBalancer = aws_lb.app[0].arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  count = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This alarm monitors the average response time"

  dimensions = {
    LoadBalancer = aws_lb.app[0].arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  count = var.enable_load_balancer && var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This alarm monitors 5xx errors from the load balancer"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app[0].arn_suffix
  }

  tags = local.common_tags
}