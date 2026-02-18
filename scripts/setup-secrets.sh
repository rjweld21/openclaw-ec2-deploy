#!/bin/bash
# OpenClaw EC2 Deployment - GitHub Secrets Setup Script
# Run this script to set up required GitHub secrets for deployment

set -e

REPO_OWNER=""
REPO_NAME=""
GITHUB_TOKEN=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${GREEN}=================================${NC}"
    echo -e "${GREEN}OpenClaw EC2 Deployment Setup${NC}"
    echo -e "${GREEN}=================================${NC}"
    echo ""
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

check_requirements() {
    echo "Checking requirements..."
    
    # Check for GitHub CLI
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi
    
    # Check for AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        echo "Install it from: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    print_success "All requirements satisfied"
}

get_repo_info() {
    echo ""
    echo "Repository Information:"
    echo "======================"
    
    if [ -z "$REPO_OWNER" ]; then
        read -p "GitHub username/organization: " REPO_OWNER
    fi
    
    if [ -z "$REPO_NAME" ]; then
        read -p "Repository name: " REPO_NAME
    fi
    
    echo "Repository: $REPO_OWNER/$REPO_NAME"
}

authenticate_github() {
    echo ""
    echo "GitHub Authentication:"
    echo "====================="
    
    if ! gh auth status &> /dev/null; then
        echo "Please authenticate with GitHub CLI..."
        gh auth login
    else
        print_success "Already authenticated with GitHub"
    fi
}

get_aws_credentials() {
    echo ""
    echo "AWS Credentials:"
    echo "================"
    
    read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    
    # Validate AWS credentials
    echo "Validating AWS credentials..."
    if aws sts get-caller-identity --region us-east-1 > /dev/null 2>&1; then
        print_success "AWS credentials are valid"
    else
        print_error "AWS credentials are invalid"
        exit 1
    fi
}

get_deployment_config() {
    echo ""
    echo "Deployment Configuration:"
    echo "========================"
    
    read -p "AWS Key Pair name (for SSH access): " AWS_KEY_PAIR_NAME
    
    echo ""
    print_warning "SSH Access Configuration"
    echo "For security, restrict SSH access to your IP address."
    echo "Current IP address: $(curl -s https://api.ipify.org)"
    echo ""
    read -p "Allowed SSH CIDR (e.g., $(curl -s https://api.ipify.org)/32): " ALLOWED_SSH_CIDR
    
    echo ""
    read -p "Domain name (optional, for SSL): " DOMAIN_NAME
    
    if [ -n "$DOMAIN_NAME" ]; then
        print_warning "Domain Configuration"
        echo "If you specified a domain, you'll need to:"
        echo "1. Configure DNS to point to the load balancer after deployment"
        echo "2. Validate the SSL certificate via DNS"
    fi
}

set_github_secrets() {
    echo ""
    echo "Setting GitHub Secrets:"
    echo "======================"
    
    # Set AWS credentials
    echo "Setting AWS_ACCESS_KEY_ID..."
    gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID" --repo "$REPO_OWNER/$REPO_NAME"
    
    echo "Setting AWS_SECRET_ACCESS_KEY..."
    gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY" --repo "$REPO_OWNER/$REPO_NAME"
    
    # Set deployment configuration
    echo "Setting AWS_KEY_PAIR_NAME..."
    gh secret set AWS_KEY_PAIR_NAME --body "$AWS_KEY_PAIR_NAME" --repo "$REPO_OWNER/$REPO_NAME"
    
    echo "Setting ALLOWED_SSH_CIDR..."
    gh secret set ALLOWED_SSH_CIDR --body "$ALLOWED_SSH_CIDR" --repo "$REPO_OWNER/$REPO_NAME"
    
    # Set domain if provided
    if [ -n "$DOMAIN_NAME" ]; then
        echo "Setting DOMAIN_NAME..."
        gh secret set DOMAIN_NAME --body "$DOMAIN_NAME" --repo "$REPO_OWNER/$REPO_NAME"
    fi
    
    print_success "All GitHub secrets have been set"
}

generate_openclaw_token() {
    echo ""
    echo "OpenClaw Gateway Token:"
    echo "======================"
    
    # Generate a secure random token
    OPENCLAW_TOKEN=$(openssl rand -hex 32)
    
    echo "Generated OpenClaw Gateway token: $OPENCLAW_TOKEN"
    echo ""
    print_warning "Important: Save this token securely!"
    echo "You'll need this token to configure your OpenClaw client."
    echo ""
    
    read -p "Press Enter to continue..."
    
    # Optionally set as GitHub secret for future reference
    read -p "Save token as GitHub secret? (y/n): " SAVE_TOKEN
    if [ "$SAVE_TOKEN" = "y" ] || [ "$SAVE_TOKEN" = "Y" ]; then
        gh secret set OPENCLAW_GATEWAY_TOKEN --body "$OPENCLAW_TOKEN" --repo "$REPO_OWNER/$REPO_NAME"
        print_success "Token saved as GitHub secret"
    fi
}

print_next_steps() {
    echo ""
    echo -e "${GREEN}Setup Complete!${NC}"
    echo "==============="
    echo ""
    echo "Next steps:"
    echo "1. Commit and push your changes to trigger deployment"
    echo "2. Monitor the GitHub Actions workflow for deployment status"
    echo "3. Once deployed, configure your OpenClaw client with the load balancer URL"
    echo "4. If using a custom domain, configure DNS records"
    echo ""
    echo "To deploy manually, run:"
    echo "  git add ."
    echo "  git commit -m 'Deploy OpenClaw to EC2'"
    echo "  git push origin main"
    echo ""
    echo "To destroy infrastructure, use GitHub Actions workflow_dispatch with 'destroy' input"
}

# Main execution
main() {
    print_header
    check_requirements
    get_repo_info
    authenticate_github
    get_aws_credentials
    get_deployment_config
    set_github_secrets
    generate_openclaw_token
    print_next_steps
}

# Check if running in CI (skip interactive parts)
if [ "$CI" = "true" ]; then
    echo "Running in CI mode - skipping interactive setup"
    exit 0
fi

# Run main function
main