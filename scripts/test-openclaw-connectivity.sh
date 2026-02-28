#!/bin/bash

# Simple OpenClaw connectivity test
# Usage: ./test-openclaw-connectivity.sh <instance-ip>

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo "Usage: $0 <instance-ip-address>"
    echo "Example: $0 54.123.45.67"
    exit 1
fi

INSTANCE_IP="$1"
GATEWAY_URL="http://$INSTANCE_IP:8080"
HEALTH_URL="http://$INSTANCE_IP:8081"

echo -e "${BLUE}🌐 Testing OpenClaw Connectivity${NC}"
echo "================================"
echo "Instance IP: $INSTANCE_IP"
echo "Gateway URL: $GATEWAY_URL"
echo "Health URL: $HEALTH_URL"
echo ""

# Test health check
echo -e "${BLUE}Testing health check endpoint...${NC}"
if response=$(curl -sf --connect-timeout 10 --max-time 30 "$HEALTH_URL/health" 2>/dev/null); then
    echo -e "${GREEN}✅ Health check successful${NC}"
    
    # Parse status if JSON
    if command -v jq &>/dev/null; then
        status=$(echo "$response" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
        openclaw_status=$(echo "$response" | jq -r '.services.openclawGateway // "unknown"' 2>/dev/null || echo "unknown")
        
        echo -e "${GREEN}   📊 Overall status: $status${NC}"
        echo -e "${GREEN}   🌐 OpenClaw Gateway: $openclaw_status${NC}"
        
        if [ "$openclaw_status" = "online" ]; then
            echo -e "${GREEN}   ✅ OpenClaw Gateway is running${NC}"
        else
            echo -e "${YELLOW}   ⚠️ OpenClaw Gateway may be starting up${NC}"
        fi
    else
        echo -e "${GREEN}   📄 Response received (install jq for detailed parsing)${NC}"
    fi
else
    echo -e "${RED}❌ Health check failed${NC}"
    echo -e "${YELLOW}💡 Instance may still be starting up (wait 2-3 minutes)${NC}"
fi

echo ""

# Test OpenClaw Gateway
echo -e "${BLUE}Testing OpenClaw Gateway...${NC}"
GATEWAY_ENDPOINTS=(
    "$GATEWAY_URL"
    "$GATEWAY_URL/health"
    "$GATEWAY_URL/status"
)

GATEWAY_RESPONDING=false
for endpoint in "${GATEWAY_ENDPOINTS[@]}"; do
    if curl -sf --connect-timeout 10 --max-time 30 "$endpoint" &>/dev/null; then
        echo -e "${GREEN}✅ Gateway responding at: $endpoint${NC}"
        GATEWAY_RESPONDING=true
        break
    fi
done

if [ "$GATEWAY_RESPONDING" = false ]; then
    echo -e "${RED}❌ OpenClaw Gateway not responding${NC}"
    echo -e "${YELLOW}💡 Gateway may still be initializing${NC}"
fi

echo ""

# Browser test
echo -e "${BLUE}🌐 Browser Access${NC}"
echo "================="
echo "Try opening these URLs in your browser:"
echo "📊 Health Dashboard: $HEALTH_URL"
echo "🌐 OpenClaw Gateway: $GATEWAY_URL"

echo ""

# Final status
if [ "$GATEWAY_RESPONDING" = true ]; then
    echo -e "${GREEN}🎉 SUCCESS: OpenClaw appears to be running!${NC}"
    echo -e "${GREEN}   Access it at: $GATEWAY_URL${NC}"
else
    echo -e "${YELLOW}⏳ OpenClaw may still be starting up${NC}"
    echo -e "${YELLOW}   Wait a few minutes and try again${NC}"
    echo -e "${YELLOW}   Initial setup can take 3-5 minutes after EC2 launch${NC}"
fi