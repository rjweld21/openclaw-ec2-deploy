#!/bin/bash

# OpenClaw EC2 Deployment Troubleshooting Script
# This script helps diagnose common deployment issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-openclaw}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

echo -e "${BLUE}🔍 OpenClaw EC2 Deployment Troubleshooting Script${NC}"
echo "=================================================="
echo

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✅ $message${NC}"
    elif [ "$status" = "WARNING" ]; then
        echo -e "${YELLOW}⚠️  $message${NC}"
    else
        echo -e "${RED}❌ $message${NC}"
    fi
}

echo "🛠️  Checking Prerequisites..."
echo "--------------------------------"

# Check required tools
if command_exists aws; then
    print_status "OK" "AWS CLI is installed"
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    echo "   Version: $AWS_VERSION"
else
    print_status "ERROR" "AWS CLI is not installed"
fi

if command_exists terraform; then
    print_status "OK" "Terraform is installed"
    TF_VERSION=$(terraform version | head -n1 | cut -d' ' -f2)
    echo "   Version: $TF_VERSION"
else
    print_status "ERROR" "Terraform is not installed"
fi

if command_exists jq; then
    print_status "OK" "jq is installed"
else
    print_status "WARNING" "jq is not installed (optional but helpful)"
fi

echo
echo "🔐 Checking AWS Configuration..."
echo "--------------------------------"

# Check AWS credentials
if aws sts get-caller-identity >/dev/null 2>&1; then
    print_status "OK" "AWS credentials are configured"
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
    CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "Not set")
    
    echo "   Account ID: $ACCOUNT_ID"
    echo "   User/Role: $CURRENT_USER"
    echo "   Region: $CURRENT_REGION"
else
    print_status "ERROR" "AWS credentials are not configured or invalid"
fi

# Check AWS region
if [ "$CURRENT_REGION" != "$AWS_REGION" ] && [ "$CURRENT_REGION" != "Not set" ]; then
    print_status "WARNING" "AWS CLI region ($CURRENT_REGION) differs from target region ($AWS_REGION)"
fi

echo
echo "📋 Checking AWS Resource Limits..."
echo "----------------------------------"

# Check VPC limits
VPC_COUNT=$(aws ec2 describe-vpcs --region "$AWS_REGION" --query 'length(Vpcs)' --output text 2>/dev/null || echo "0")
if [ "$VPC_COUNT" -ge 5 ]; then
    print_status "WARNING" "VPC limit approaching: $VPC_COUNT/5 VPCs in use"
else
    print_status "OK" "VPC usage: $VPC_COUNT/5"
fi

# Check EIP limits
EIP_COUNT=$(aws ec2 describe-addresses --region "$AWS_REGION" --query 'length(Addresses)' --output text 2>/dev/null || echo "0")
if [ "$EIP_COUNT" -ge 5 ]; then
    print_status "WARNING" "Elastic IP limit approaching: $EIP_COUNT/5 EIPs in use"
else
    print_status "OK" "Elastic IP usage: $EIP_COUNT/5"
fi

echo
echo "🏗️  Checking Terraform Configuration..."
echo "--------------------------------------"

# Check if terraform files exist
if [ -f "backend.tf" ]; then
    print_status "OK" "backend.tf exists"
else
    print_status "ERROR" "backend.tf not found"
fi

if [ -f "variables.tf" ]; then
    print_status "OK" "variables.tf exists"
else
    print_status "ERROR" "variables.tf not found"
fi

if [ -f "terraform.tfvars" ]; then
    print_status "OK" "terraform.tfvars exists"
else
    if [ -f "terraform.tfvars.example" ]; then
        print_status "WARNING" "terraform.tfvars not found, but terraform.tfvars.example exists"
        echo "   Run: cp terraform.tfvars.example terraform.tfvars"
    else
        print_status "ERROR" "terraform.tfvars not found"
    fi
fi

# Check Terraform initialization
if [ -d ".terraform" ]; then
    print_status "OK" "Terraform is initialized"
    
    # Check backend configuration
    if [ -f ".terraform/terraform.tfstate" ]; then
        BACKEND_TYPE=$(cat .terraform/terraform.tfstate | jq -r '.backend.type' 2>/dev/null || echo "unknown")
        if [ "$BACKEND_TYPE" = "s3" ]; then
            print_status "OK" "S3 backend configured"
            BUCKET=$(cat .terraform/terraform.tfstate | jq -r '.backend.config.bucket' 2>/dev/null)
            echo "   Bucket: $BUCKET"
        else
            print_status "WARNING" "Backend type: $BACKEND_TYPE"
        fi
    fi
else
    print_status "WARNING" "Terraform not initialized. Run: terraform init"
fi

echo
echo "🔍 Checking AWS Resource Availability..."
echo "---------------------------------------"

# Check AMI availability
echo "Checking latest Amazon Linux 2 AMI..."
LATEST_AMI=$(aws ec2 describe-images \
    --region "$AWS_REGION" \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text 2>/dev/null || echo "")

if [ -n "$LATEST_AMI" ] && [ "$LATEST_AMI" != "None" ]; then
    print_status "OK" "Latest AMI found: $LATEST_AMI"
else
    print_status "ERROR" "Could not find latest Amazon Linux 2 AMI"
fi

# Check availability zones
echo "Checking availability zones..."
AZ_COUNT=$(aws ec2 describe-availability-zones --region "$AWS_REGION" --query 'length(AvailabilityZones[?State==`available`])' --output text 2>/dev/null || echo "0")
if [ "$AZ_COUNT" -ge 2 ]; then
    print_status "OK" "Available zones: $AZ_COUNT"
else
    print_status "ERROR" "Insufficient availability zones: $AZ_COUNT (need at least 2)"
fi

# Check instance type availability
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
echo "Checking instance type availability: $INSTANCE_TYPE"
INSTANCE_AVAILABLE=$(aws ec2 describe-instance-type-offerings \
    --region "$AWS_REGION" \
    --filters "Name=instance-type,Values=$INSTANCE_TYPE" \
    --query 'length(InstanceTypeOfferings)' \
    --output text 2>/dev/null || echo "0")

if [ "$INSTANCE_AVAILABLE" -gt 0 ]; then
    print_status "OK" "Instance type $INSTANCE_TYPE is available"
else
    print_status "ERROR" "Instance type $INSTANCE_TYPE is not available in $AWS_REGION"
fi

echo
echo "🔒 Checking IAM Permissions..."
echo "------------------------------"

# Test basic EC2 permissions
if aws ec2 describe-instances --region "$AWS_REGION" --max-items 1 >/dev/null 2>&1; then
    print_status "OK" "EC2 describe permissions"
else
    print_status "ERROR" "Missing EC2 describe permissions"
fi

# Test VPC permissions
if aws ec2 describe-vpcs --region "$AWS_REGION" --max-items 1 >/dev/null 2>&1; then
    print_status "OK" "VPC describe permissions"
else
    print_status "ERROR" "Missing VPC describe permissions"
fi

# Test Auto Scaling permissions
if aws autoscaling describe-auto-scaling-groups --region "$AWS_REGION" --max-items 1 >/dev/null 2>&1; then
    print_status "OK" "Auto Scaling describe permissions"
else
    print_status "ERROR" "Missing Auto Scaling describe permissions"
fi

# Test Load Balancer permissions
if aws elbv2 describe-load-balancers --region "$AWS_REGION" --page-size 1 >/dev/null 2>&1; then
    print_status "OK" "Load Balancer describe permissions"
else
    print_status "ERROR" "Missing Load Balancer describe permissions"
fi

echo
echo "🚀 Checking Existing Deployment..."
echo "----------------------------------"

# Check for existing resources
ASG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-asg"
if aws autoscaling describe-auto-scaling-groups --region "$AWS_REGION" --auto-scaling-group-names "$ASG_NAME" >/dev/null 2>&1; then
    print_status "OK" "Auto Scaling Group exists: $ASG_NAME"
    
    # Get ASG details
    DESIRED=$(aws autoscaling describe-auto-scaling-groups --region "$AWS_REGION" --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
    RUNNING=$(aws autoscaling describe-auto-scaling-groups --region "$AWS_REGION" --auto-scaling-group-names "$ASG_NAME" --query 'length(AutoScalingGroups[0].Instances[?LifecycleState==`InService`])' --output text)
    
    echo "   Desired: $DESIRED, Running: $RUNNING"
    
    if [ "$RUNNING" != "$DESIRED" ]; then
        print_status "WARNING" "Instance count mismatch"
    fi
else
    print_status "WARNING" "Auto Scaling Group not found (not deployed yet?)"
fi

# Check for load balancer
ALB_NAME="${PROJECT_NAME}-${ENVIRONMENT}-alb"
if aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" >/dev/null 2>&1; then
    print_status "OK" "Load Balancer exists: $ALB_NAME"
    
    # Get ALB DNS name
    DNS_NAME=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" --query 'LoadBalancers[0].DNSName' --output text)
    echo "   DNS: $DNS_NAME"
    
    # Check target health
    TG_ARN=$(aws elbv2 describe-target-groups --region "$AWS_REGION" --names "${PROJECT_NAME}-${ENVIRONMENT}-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
    if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
        HEALTHY_TARGETS=$(aws elbv2 describe-target-health --region "$AWS_REGION" --target-group-arn "$TG_ARN" --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text 2>/dev/null || echo "0")
        TOTAL_TARGETS=$(aws elbv2 describe-target-health --region "$AWS_REGION" --target-group-arn "$TG_ARN" --query 'length(TargetHealthDescriptions)' --output text 2>/dev/null || echo "0")
        echo "   Healthy targets: $HEALTHY_TARGETS/$TOTAL_TARGETS"
        
        if [ "$HEALTHY_TARGETS" -eq 0 ] && [ "$TOTAL_TARGETS" -gt 0 ]; then
            print_status "ERROR" "No healthy targets"
        fi
    fi
else
    print_status "WARNING" "Load Balancer not found"
fi

echo
echo "📊 Summary and Recommendations..."
echo "---------------------------------"

# Provide recommendations based on findings
if [ "$VPC_COUNT" -ge 4 ]; then
    echo -e "${YELLOW}💡 Consider cleaning up unused VPCs before deployment${NC}"
fi

if [ "$CURRENT_REGION" != "$AWS_REGION" ] && [ "$CURRENT_REGION" != "Not set" ]; then
    echo -e "${YELLOW}💡 Set AWS CLI region: aws configure set region $AWS_REGION${NC}"
fi

if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}💡 Create terraform.tfvars: cp terraform.tfvars.example terraform.tfvars${NC}"
fi

if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}💡 Initialize Terraform: terraform init${NC}"
fi

echo
echo "🔧 Common Troubleshooting Commands..."
echo "------------------------------------"
echo "# Check Terraform plan:"
echo "terraform plan"
echo
echo "# View current state:"
echo "terraform state list"
echo
echo "# Check resource dependencies:"
echo "terraform graph | dot -Tsvg > graph.svg"
echo
echo "# Debug AWS permissions:"
echo "aws iam simulate-principal-policy --policy-source-arn \$(aws sts get-caller-identity --query Arn --output text) --action-names ec2:RunInstances --resource-arns '*'"
echo
echo "# Check application logs:"
echo "aws logs tail /aws/ec2/${PROJECT_NAME}-${ENVIRONMENT} --follow"
echo
echo "# Connect to instance via Session Manager:"
echo "aws ssm start-session --target \$(aws ec2 describe-instances --filters 'Name=tag:Project,Values=${PROJECT_NAME}' --query 'Reservations[0].Instances[0].InstanceId' --output text)"

echo
echo -e "${GREEN}✨ Troubleshooting complete!${NC}"
echo

exit 0