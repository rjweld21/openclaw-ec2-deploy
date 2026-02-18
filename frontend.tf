# Frontend S3 and CloudFront configuration for OpenClaw React app
# This creates the infrastructure to serve a React application

# S3 bucket for frontend hosting
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-${var.environment}-frontend-${random_id.frontend_suffix.hex}"

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-${var.environment}-frontend"
    Purpose = "static-website-hosting"
  })
}

resource "random_id" "frontend_suffix" {
  byte_length = 4
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket public access block (initially blocked, will be managed via CloudFront)
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudFront access
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_s3_policy.json
}

data "aws_iam_policy_document" "frontend_s3_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.frontend.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-${var.environment}-frontend-oac"
  description                       = "Origin Access Control for OpenClaw Frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution for React frontend
resource "aws_cloudfront_distribution" "frontend" {
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
  }

  # Origin for API backend (ALB or direct EC2)
  dynamic "origin" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      domain_name = aws_lb.app[0].dns_name
      origin_id   = "ALB-${var.project_name}-${var.environment}"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "http-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "OpenClaw ${var.environment} Frontend Distribution"
  default_root_object = "index.html"

  # Cache behavior for frontend assets (React app)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    compress = true
  }

  # Cache behavior for API calls
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      path_pattern     = "/api/*"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "ALB-${var.project_name}-${var.environment}"

      forwarded_values {
        query_string = true
        headers      = ["*"]
        cookies {
          forward = "all"
        }
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
      compress               = false
    }
  }

  # Cache behavior for health checks
  ordered_cache_behavior {
    path_pattern     = "/health"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.enable_load_balancer ? "ALB-${var.project_name}-${var.environment}" : "S3-${aws_s3_bucket.frontend.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 60
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-cloudfront"
  })

  viewer_certificate {
    cloudfront_default_certificate = var.ssl_certificate_arn == ""
    
    dynamic "acm_certificate_arn" {
      for_each = var.ssl_certificate_arn != "" ? [1] : []
      content {
        acm_certificate_arn = var.ssl_certificate_arn
        ssl_support_method  = "sni-only"
      }
    }
  }

  # Custom error responses for React SPA
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }
}

# S3 bucket for frontend build artifacts (used by GitHub Actions)
resource "aws_s3_bucket" "frontend_artifacts" {
  bucket = "${var.project_name}-${var.environment}-frontend-artifacts-${random_id.frontend_artifacts_suffix.hex}"

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-${var.environment}-frontend-artifacts"
    Purpose = "build-artifacts"
  })
}

resource "random_id" "frontend_artifacts_suffix" {
  byte_length = 4
}

# S3 bucket lifecycle for artifacts cleanup
resource "aws_s3_bucket_lifecycle_configuration" "frontend_artifacts" {
  bucket = aws_s3_bucket.frontend_artifacts.id

  rule {
    id     = "artifact_cleanup"
    status = "Enabled"

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 3
    }
  }
}

# CloudWatch invalidation function for cache busting
resource "aws_lambda_function" "cache_invalidation" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  filename         = "cache_invalidation.zip"
  function_name    = "${var.project_name}-${var.environment}-cache-invalidation"
  role            = aws_iam_role.lambda_cache_invalidation[0].arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.cache_invalidation_zip[0].output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      DISTRIBUTION_ID = aws_cloudfront_distribution.frontend.id
    }
  }

  tags = local.common_tags
}

# Lambda deployment package
data "archive_file" "cache_invalidation_zip" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  type        = "zip"
  output_path = "cache_invalidation.zip"
  
  source {
    content = <<EOF
import boto3
import json
import os

def handler(event, context):
    cloudfront = boto3.client('cloudfront')
    distribution_id = os.environ['DISTRIBUTION_ID']
    
    try:
        response = cloudfront.create_invalidation(
            DistributionId=distribution_id,
            InvalidationBatch={
                'Paths': {
                    'Quantity': 1,
                    'Items': ['/*']
                },
                'CallerReference': str(context.aws_request_id)
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cache invalidation created',
                'invalidation_id': response['Invalidation']['Id']
            })
        }
    except Exception as e:
        print(f"Error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    filename = "index.py"
  }
}

# IAM role for Lambda cache invalidation
resource "aws_iam_role" "lambda_cache_invalidation" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name = "${var.project_name}-${var.environment}-lambda-cache-invalidation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda_cache_invalidation" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name = "${var.project_name}-${var.environment}-lambda-cache-invalidation"
  role = aws_iam_role.lambda_cache_invalidation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation"
        ]
        Resource = aws_cloudfront_distribution.frontend.arn
      }
    ]
  })
}