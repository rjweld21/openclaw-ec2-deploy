# EC2 and Auto Scaling configuration
# Addresses AMI availability, instance type availability, launch template validation,
# auto scaling group health checks, and user data script issues

# Launch template for EC2 instances
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-${var.environment}-"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux[0].id
  instance_type = var.instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null

  vpc_security_group_ids = [aws_security_group.app.id]

  # IAM instance profile
  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  # EBS optimization
  ebs_optimized = true

  # Block device mappings
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      iops                 = 3000
      throughput           = 125
      delete_on_termination = true
      encrypted            = true
    }
  }

  # User data script (base64 encoded, size-optimized)
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    openclaw_port    = var.openclaw_port
    openclaw_version = var.openclaw_version
    project_name     = var.project_name
    environment      = var.environment
    aws_region       = var.aws_region
  }))

  # Monitoring
  monitoring {
    enabled = var.enable_cloudwatch_monitoring
  }

  # Metadata options for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Tag specifications
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-instance"
      Type = "application"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-volume"
      Type = "application"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-launch-template"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-${var.environment}-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = var.enable_load_balancer ? [aws_lb_target_group.app[0].arn] : []
  health_check_type   = var.enable_load_balancer ? "ELB" : "EC2"
  
  # Health check grace period - increased for application startup time
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # Launch template configuration
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Instance refresh configuration
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup       = 300
    }
    triggers = ["tag"]
  }

  # Termination policies
  termination_policies = ["OldestInstance"]

  # Enable instance protection
  protect_from_scale_in = false

  # Capacity rebalancing for Spot instances (if using mixed instances)
  capacity_rebalance = false

  # Tags
  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # Lifecycle hook for graceful shutdown
  initial_lifecycle_hook {
    name                 = "graceful-shutdown"
    default_result       = "ABANDON"
    heartbeat_timeout    = 300
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes       = [desired_capacity]  # Allow manual scaling
  }

  depends_on = [
    aws_lb_target_group.app
  ]
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-${var.environment}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type           = "SimpleScaling"
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-${var.environment}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type           = "SimpleScaling"
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  tags = local.common_tags
}

# IAM role for EC2 instances
resource "aws_iam_role" "app" {
  name = "${var.project_name}-${var.environment}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM instance profile
resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-${var.environment}-instance-profile"
  role = aws_iam_role.app.name

  tags = local.common_tags
}

# IAM policies for EC2 instances
resource "aws_iam_role_policy" "app" {
  name = "${var.project_name}-${var.environment}-instance-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.project_name}-${var.environment}-*/*"
      }
    ]
  })
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Auto Scaling Notifications
resource "aws_sns_topic" "asg_notifications" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name = "${var.project_name}-${var.environment}-asg-notifications"

  tags = local.common_tags
}

resource "aws_autoscaling_notification" "app" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  group_names = [aws_autoscaling_group.app.name]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.asg_notifications[0].arn
}

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "app" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name              = "/aws/ec2/${var.project_name}-${var.environment}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-app-logs"
  })
}

# EBS Snapshot lifecycle policy for backups
resource "aws_dlm_lifecycle_policy" "app_snapshots" {
  count = var.backup_retention_days > 0 ? 1 : 0

  description        = "OpenClaw EBS snapshot lifecycle policy"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state             = "ENABLED"

  policy_details {
    resource_types   = ["VOLUME"]
    target_tags = {
      Project = var.project_name
    }

    schedule {
      name = "Daily snapshots"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = var.backup_retention_days
      }

      tags_to_add = merge(local.common_tags, {
        SnapshotCreator = "dlm"
      })

      copy_tags = true
    }
  }

  tags = local.common_tags
}

# IAM role for DLM
resource "aws_iam_role" "dlm" {
  count = var.backup_retention_days > 0 ? 1 : 0

  name = "${var.project_name}-${var.environment}-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  count = var.backup_retention_days > 0 ? 1 : 0

  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}