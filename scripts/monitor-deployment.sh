#!/bin/bash

# Enhanced GitHub Actions Monitoring Script for OpenClaw EC2 Deployment
# This script monitors the CI/CD pipeline status and infrastructure deployment

set -euo pipefail

echo "🚀 OpenClaw CI/CD Pipeline Monitor"
echo "=================================="
echo "Monitoring deployment status..."
echo ""

# Configuration
REPO_NAME="rjweld21/openclaw-ec2-deploy"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Function to check GitHub Actions status
check_github_actions() {
    echo "📊 GitHub Actions Status:"
    echo "------------------------"
    
    # Check if GitHub CLI is available
    if command -v gh &> /dev/null; then
        echo "Using GitHub CLI to check workflow status..."
        gh run list --repo $REPO_NAME --limit 3 --json status,conclusion,workflowName,createdAt,url
    else
        echo "⚠️ GitHub CLI not available. Please check workflow status manually at:"
        echo "   https://github.com/$REPO_NAME/actions"
    fi
    echo ""
}

# Function to check AWS infrastructure
check_aws_infrastructure() {
    echo "🏗️ AWS Infrastructure Status:"
    echo "-----------------------------"
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI not available. Cannot check infrastructure status."
        return
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials not configured. Cannot check infrastructure status."
        return
    fi
    
    echo "✅ AWS CLI configured. Checking infrastructure..."
    
    # Check for OpenClaw VPCs
    echo "🌐 VPC Status:"
    VPC_COUNT=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=openclaw" --query 'Vpcs' --output json | jq length)
    echo "   OpenClaw VPCs found: $VPC_COUNT"
    
    # Check for OpenClaw security groups
    echo "🔒 Security Groups:"
    SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=tag:Project,Values=openclaw" --query 'SecurityGroups' --output json | jq length)
    echo "   OpenClaw Security Groups: $SG_COUNT"
    
    if [ $SG_COUNT -gt 0 ]; then
        echo "   Security Group Details:"
        aws ec2 describe-security-groups \
            --filters "Name=tag:Project,Values=openclaw" \
            --query 'SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName,Description:Description}' \
            --output table
    fi
    
    # Check for OpenClaw EC2 instances
    echo "💻 EC2 Instances:"
    INSTANCE_COUNT=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=openclaw" "Name=instance-state-name,Values=running,pending,stopping,stopped" --query 'Reservations[*].Instances' --output json | jq '[.[]] | length')
    echo "   OpenClaw Instances: $INSTANCE_COUNT"
    
    if [ $INSTANCE_COUNT -gt 0 ]; then
        echo "   Instance Details:"
        aws ec2 describe-instances \
            --filters "Name=tag:Project,Values=openclaw" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
            --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,State:State.Name,Type:InstanceType,PublicIP:PublicIpAddress}' \
            --output table
    fi
    
    # Check for Load Balancers
    echo "⚖️ Load Balancers:"
    ALB_COUNT=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `openclaw`)]' --output json | jq length)
    echo "   OpenClaw Load Balancers: $ALB_COUNT"
    
    if [ $ALB_COUNT -gt 0 ]; then
        echo "   Load Balancer Details:"
        aws elbv2 describe-load-balancers \
            --query 'LoadBalancers[?contains(LoadBalancerName, `openclaw`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}' \
            --output table
    fi
    
    # Check Auto Scaling Groups
    echo "📈 Auto Scaling Groups:"
    ASG_COUNT=$(aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `openclaw`)]' --output json | jq length)
    echo "   OpenClaw ASGs: $ASG_COUNT"
    
    if [ $ASG_COUNT -gt 0 ]; then
        echo "   ASG Details:"
        aws autoscaling describe-auto-scaling-groups \
            --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `openclaw`)].{Name:AutoScalingGroupName,MinSize:MinSize,MaxSize:MaxSize,DesiredCapacity:DesiredCapacity,HealthCheckType:HealthCheckType}' \
            --output table
    fi
    
    echo ""
}

# Function to check application health
check_application_health() {
    echo "🏥 Application Health Status:"
    echo "----------------------------"
    
    # Get Load Balancer DNS
    if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
        ALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `openclaw`)].DNSName' --output text 2>/dev/null || echo "")
        
        if [ -n "$ALB_DNS" ]; then
            echo "🌐 Testing Load Balancer: http://$ALB_DNS"
            
            # Test basic connectivity
            if curl -f --max-time 10 "http://$ALB_DNS" > /dev/null 2>&1; then
                echo "✅ Base URL responding"
            else
                echo "❌ Base URL not responding"
            fi
            
            # Test health endpoint
            if curl -f --max-time 10 "http://$ALB_DNS/health" > /dev/null 2>&1; then
                echo "✅ Health endpoint responding"
                echo "Health check response:"
                curl -s --max-time 10 "http://$ALB_DNS/health" | jq '.' 2>/dev/null || curl -s --max-time 10 "http://$ALB_DNS/health"
            else
                echo "❌ Health endpoint not responding"
            fi
        else
            echo "⚠️ No Load Balancer found or not accessible"
        fi
    else
        echo "⚠️ Cannot check application health - AWS CLI not configured"
    fi
    
    echo ""
}

# Function to check CloudWatch logs
check_cloudwatch_logs() {
    echo "📝 CloudWatch Logs:"
    echo "------------------"
    
    if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
        # Check for OpenClaw log groups
        LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/openclaw" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
        
        if [ -n "$LOG_GROUPS" ]; then
            echo "📋 Found log groups:"
            for LOG_GROUP in $LOG_GROUPS; do
                echo "   - $LOG_GROUP"
                
                # Get recent log events
                echo "   Recent entries (last 5):"
                aws logs describe-log-streams --log-group-name "$LOG_GROUP" --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text | xargs -I {} aws logs get-log-events --log-group-name "$LOG_GROUP" --log-stream-name {} --limit 5 --query 'events[*].[timestamp,message]' --output text 2>/dev/null | tail -5 | while read -r timestamp message; do
                    DATE=$(date -d "@$((timestamp/1000))" 2>/dev/null || date -r $((timestamp/1000)) 2>/dev/null || echo "Unknown")
                    echo "     [$DATE] $message"
                done 2>/dev/null || echo "     No recent log entries available"
            done
        else
            echo "⚠️ No CloudWatch log groups found"
        fi
    else
        echo "⚠️ Cannot check CloudWatch logs - AWS CLI not configured"
    fi
    
    echo ""
}

# Function to show next steps
show_next_steps() {
    echo "🎯 Next Steps:"
    echo "-------------"
    echo ""
    echo "1. 📊 Monitor GitHub Actions:"
    echo "   https://github.com/$REPO_NAME/actions"
    echo ""
    echo "2. 🔍 If deployment successful, verify application:"
    echo "   - Check Load Balancer URL for OpenClaw Gateway"
    echo "   - Test /health endpoint"
    echo "   - Verify all security groups are properly configured"
    echo ""
    echo "3. 🔧 If deployment failed:"
    echo "   - Check GitHub Actions logs for specific errors"
    echo "   - Verify AWS credentials and permissions"
    echo "   - Check Terraform state and backend configuration"
    echo ""
    echo "4. 🛡️ Security Review:"
    echo "   - Review security group rules (currently open to 0.0.0.0/0)"
    echo "   - Consider restricting access to specific IP ranges"
    echo "   - Set up monitoring alerts"
    echo ""
    echo "5. 📈 Performance Optimization:"
    echo "   - Monitor CloudWatch metrics"
    echo "   - Adjust Auto Scaling Group parameters if needed"
    echo "   - Review instance types and sizes"
    echo ""
}

# Main execution
main() {
    check_github_actions
    check_aws_infrastructure
    check_application_health
    check_cloudwatch_logs
    show_next_steps
    
    echo "🏁 Monitoring complete!"
    echo ""
    echo "💡 Tip: Run this script periodically to track deployment progress"
    echo "   or set up AWS CloudWatch alarms for automated monitoring."
}

# Execute main function
main "$@"