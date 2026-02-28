#!/bin/bash

# Remote OpenClaw Validation Script
# Run this from your local machine to validate OpenClaw installation on EC2

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 OpenClaw Remote Validation${NC}"
echo "=================================="

# Get instance information from terraform output
echo -e "${BLUE}📊 Getting instance information...${NC}"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform not found. Please install Terraform first.${NC}"
    exit 1
fi

cd "$(dirname "$0")/../terraform"

if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}❌ Terraform state file not found. Please run terraform apply first.${NC}"
    exit 1
fi

INSTANCE_IP=$(terraform output -raw instance_public_ip 2>/dev/null)
GATEWAY_URL=$(terraform output -raw openclaw_gateway_url 2>/dev/null)
HEALTH_URL=$(terraform output -raw health_check_url 2>/dev/null)

if [ -z "$INSTANCE_IP" ]; then
    echo -e "${RED}❌ Could not get instance IP from Terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Instance IP: $INSTANCE_IP${NC}"
echo -e "${GREEN}✅ Gateway URL: $GATEWAY_URL${NC}"
echo -e "${GREEN}✅ Health URL: $HEALTH_URL${NC}"

# Test 1: Basic connectivity
echo ""
echo -e "${BLUE}1. Testing basic connectivity...${NC}"
if ping -c 1 -W 3 "$INSTANCE_IP" &>/dev/null; then
    echo -e "${GREEN}   ✅ Instance is reachable via ping${NC}"
else
    echo -e "${YELLOW}   ⚠️ Instance ping failed (may be normal if ICMP is blocked)${NC}"
fi

# Test 2: SSH connectivity
echo ""
echo -e "${BLUE}2. Testing SSH connectivity...${NC}"
SSH_KEY="../openclaw-ec2-key.pem"

if [ ! -f "$SSH_KEY" ]; then
    echo -e "${YELLOW}   ⚠️ SSH key not found at $SSH_KEY${NC}"
    echo -e "${YELLOW}   💡 You may need to save the private key from Terraform output${NC}"
else
    chmod 600 "$SSH_KEY"
    if timeout 10 ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$INSTANCE_IP" 'echo "SSH connection successful"' &>/dev/null; then
        echo -e "${GREEN}   ✅ SSH connection successful${NC}"
    else
        echo -e "${RED}   ❌ SSH connection failed${NC}"
        echo -e "${YELLOW}   💡 Check security groups allow SSH (port 22)${NC}"
    fi
fi

# Test 3: Health check endpoint
echo ""
echo -e "${BLUE}3. Testing health check endpoint (port 8081)...${NC}"
if curl -sf --connect-timeout 10 "$HEALTH_URL/health" &>/dev/null; then
    echo -e "${GREEN}   ✅ Health check endpoint responding${NC}"
    
    # Get health status
    HEALTH_STATUS=$(curl -sf --connect-timeout 10 "$HEALTH_URL/health" | jq -r '.status' 2>/dev/null || echo "unknown")
    echo -e "${GREEN}   📊 Health status: $HEALTH_STATUS${NC}"
else
    echo -e "${RED}   ❌ Health check endpoint not responding${NC}"
    echo -e "${YELLOW}   💡 Check security groups allow port 8081${NC}"
fi

# Test 4: OpenClaw Gateway endpoint
echo ""
echo -e "${BLUE}4. Testing OpenClaw Gateway (port 8080)...${NC}"
GATEWAY_TEST_URLS=(
    "$GATEWAY_URL"
    "$GATEWAY_URL/health"
    "$GATEWAY_URL/status"
)

GATEWAY_WORKING=false
for url in "${GATEWAY_TEST_URLS[@]}"; do
    if curl -sf --connect-timeout 10 "$url" &>/dev/null; then
        echo -e "${GREEN}   ✅ OpenClaw Gateway responding at: $url${NC}"
        GATEWAY_WORKING=true
        break
    fi
done

if [ "$GATEWAY_WORKING" = false ]; then
    echo -e "${RED}   ❌ OpenClaw Gateway not responding on port 8080${NC}"
    echo -e "${YELLOW}   💡 Check security groups allow port 8080${NC}"
    echo -e "${YELLOW}   💡 Gateway may still be starting up (try again in a few minutes)${NC}"
fi

# Test 5: Remote validation script
echo ""
echo -e "${BLUE}5. Running remote validation script...${NC}"
if [ -f "$SSH_KEY" ]; then
    if timeout 30 ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$INSTANCE_IP" 'sudo -u openclaw /opt/openclaw/validate-installation.sh' 2>/dev/null; then
        echo -e "${GREEN}   ✅ Remote validation completed${NC}"
    else
        echo -e "${RED}   ❌ Remote validation failed${NC}"
        echo -e "${YELLOW}   💡 Instance may still be initializing${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️ Skipping remote validation (SSH key not available)${NC}"
fi

# Test 6: Browser connectivity test
echo ""
echo -e "${BLUE}6. Browser connectivity test...${NC}"
echo -e "${GREEN}   🌐 You should be able to access these URLs in your browser:${NC}"
echo -e "${GREEN}   📊 Health Dashboard: $HEALTH_URL${NC}"
echo -e "${GREEN}   🌐 OpenClaw Gateway: $GATEWAY_URL${NC}"

# Summary
echo ""
echo -e "${BLUE}📋 Validation Summary${NC}"
echo "====================="

# Quick connectivity test
if curl -sf --connect-timeout 5 "$HEALTH_URL/health" &>/dev/null; then
    echo -e "${GREEN}✅ OpenClaw installation appears to be working${NC}"
    echo -e "${GREEN}   Access your OpenClaw instance at: $GATEWAY_URL${NC}"
    echo -e "${GREEN}   Health dashboard at: $HEALTH_URL${NC}"
else
    echo -e "${YELLOW}⚠️ OpenClaw may still be starting up${NC}"
    echo -e "${YELLOW}   Wait 2-3 minutes and try accessing: $GATEWAY_URL${NC}"
fi

# Next steps
echo ""
echo -e "${BLUE}🔄 Next Steps${NC}"
echo "============="
echo "1. 🌐 Open in browser: $GATEWAY_URL"
echo "2. 📊 Check health: $HEALTH_URL"
echo "3. 🔍 SSH to instance: ssh -i $SSH_KEY ubuntu@$INSTANCE_IP"
echo "4. 📝 View logs: ssh -i $SSH_KEY ubuntu@$INSTANCE_IP 'sudo -u openclaw pm2 logs'"
echo "5. 📊 Check PM2 status: ssh -i $SSH_KEY ubuntu@$INSTANCE_IP 'sudo -u openclaw pm2 status'"

echo ""
echo -e "${BLUE}💡 Troubleshooting${NC}"
echo "=================="
if [ "$GATEWAY_WORKING" = false ]; then
    echo "🔧 If OpenClaw Gateway is not responding:"
    echo "   - Wait 3-5 minutes for full initialization"
    echo "   - Check PM2 status: sudo -u openclaw pm2 status"
    echo "   - View logs: sudo -u openclaw pm2 logs"
    echo "   - Restart services: sudo -u openclaw pm2 restart all"
fi

echo "🔧 Common issues:"
echo "   - Security groups: Ensure ports 8080, 8081 are open"
echo "   - Instance startup: Initial setup takes 3-5 minutes"
echo "   - SSH key: Save private key from terraform output if missing"

echo ""
echo -e "${GREEN}✅ Validation script completed${NC}"