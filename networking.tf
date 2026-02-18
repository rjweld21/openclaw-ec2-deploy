# VPC and networking configuration
# Addresses VPC CIDR conflicts, subnet AZ distribution, route tables, and security groups

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
  
  lifecycle {
    # Prevent accidental destruction of VPC
    prevent_destroy = false  # Set to true in production
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
  
  # Ensure VPC is created first
  depends_on = [aws_vpc.main]
}

# Public subnets (one per AZ for high availability)
resource "aws_subnet" "public" {
  count = length(local.validated_azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.validated_azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-subnet-${count.index + 1}"
    Type = "public"
    AZ   = local.validated_azs[count.index]
  })
  
  lifecycle {
    # Prevent subnet destruction if instances are running
    create_before_destroy = true
  }
}

# Private subnets (one per AZ for high availability)
resource "aws_subnet" "private" {
  count = length(local.validated_azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)  # Offset to avoid conflicts
  availability_zone = local.validated_azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-subnet-${count.index + 1}"
    Type = "private"
    AZ   = local.validated_azs[count.index]
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = length(local.validated_azs)

  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
  })

  # Ensure IGW is created first
  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways for private subnet internet access
resource "aws_nat_gateway" "main" {
  count = length(local.validated_azs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
    Type = "public"
  })
}

# Route table associations for public subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route tables for private subnets (one per AZ for NAT Gateway)
resource "aws_route_table" "private" {
  count = length(local.validated_azs)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}"
    Type = "private"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security group for Application Load Balancer
resource "aws_security_group" "alb" {
  count = var.enable_load_balancer ? 1 : 0

  name_prefix = "${var.project_name}-${var.environment}-alb-"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # HTTP access
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTPS access (if SSL certificate is provided)
  dynamic "ingress" {
    for_each = var.ssl_certificate_arn != "" ? [1] : []
    content {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  # Outbound traffic to application instances
  egress {
    description     = "To application instances"
    from_port       = var.openclaw_port
    to_port         = var.openclaw_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # Health check traffic
  egress {
    description     = "Health checks"
    from_port       = var.openclaw_port
    to_port         = var.openclaw_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-alb-sg"
    Type = "load-balancer"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for application instances
resource "aws_security_group" "app" {
  name_prefix = "${var.project_name}-${var.environment}-app-"
  description = "Security group for OpenClaw application instances"
  vpc_id      = aws_vpc.main.id

  # Application port from load balancer
  ingress {
    description     = "Application traffic from ALB"
    from_port       = var.openclaw_port
    to_port         = var.openclaw_port
    protocol        = "tcp"
    security_groups = var.enable_load_balancer ? [aws_security_group.alb[0].id] : []
    cidr_blocks     = var.enable_load_balancer ? [] : var.allowed_cidr_blocks
  }

  # SSH access (if key pair is specified)
  dynamic "ingress" {
    for_each = var.key_pair_name != "" ? [1] : []
    content {
      description = "SSH access"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]  # Only from VPC by default
    }
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-app-sg"
    Type = "application"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Network ACLs for additional security layer
resource "aws_network_acl" "main" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)

  # Allow HTTP/HTTPS inbound
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    from_port  = 80
    to_port    = 80
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  ingress {
    rule_no    = 101
    protocol   = "tcp"
    from_port  = 443
    to_port    = 443
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  # Allow application port
  ingress {
    rule_no    = 102
    protocol   = "tcp"
    from_port  = var.openclaw_port
    to_port    = var.openclaw_port
    cidr_block = var.vpc_cidr
    action     = "allow"
  }

  # Allow ephemeral ports for return traffic
  ingress {
    rule_no    = 103
    protocol   = "tcp"
    from_port  = 1024
    to_port    = 65535
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  # Allow all outbound traffic
  egress {
    rule_no    = 100
    protocol   = "-1"
    from_port  = 0
    to_port    = 0
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nacl"
  })
}

# VPC Flow Logs for monitoring
resource "aws_flow_log" "main" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-flow-log"
  })
}

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name              = "/aws/vpc/${var.project_name}-${var.environment}-flow-log"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-flow-log-group"
  })
}

# IAM role for VPC Flow Logs
resource "aws_iam_role" "flow_log" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name = "${var.project_name}-${var.environment}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM role policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name = "${var.project_name}-${var.environment}-flow-log-policy"
  role = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}