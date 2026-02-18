#!/bin/bash
# OpenClaw EC2 Deployment - Monitoring and Health Check Script

set -e

# Configuration
HEALTH_TIMEOUT=10
LOG_FILE="deployment-monitor.log"
CHECK_INTERVAL=30

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

print_status() {
    echo -e "${BLUE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

get_load_balancer_dns() {
    local dns_name=""
    
    # Try to get from Terraform output
    if [ -f "../infrastructure/terraform.tfstate" ]; then
        dns_name=$(terraform -chdir=../infrastructure output -raw load_balancer_dns 2>/dev/null || echo "")
    fi
    
    # If not available, prompt user
    if [ -z "$dns_name" ]; then
        read -p "Enter your load balancer DNS name: " dns_name
    fi
    
    echo "$dns_name"
}

check_health() {
    local url="$1"
    local timeout="${2:-$HEALTH_TIMEOUT}"
    
    if curl -f -s --max-time "$timeout" "$url/health" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_openclaw_gateway() {
    local url="$1"
    local timeout="${2:-$HEALTH_TIMEOUT}"
    
    # Try to access the main OpenClaw endpoint
    local response=$(curl -s --max-time "$timeout" -w "%{http_code}" -o /dev/null "$url" 2>/dev/null || echo "000")
    
    # OpenClaw typically returns 401 for unauthenticated requests, which is expected
    if [ "$response" = "401" ] || [ "$response" = "200" ]; then
        return 0
    else
        return 1
    fi
}

check_ssl() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        return 0  # Skip SSL check if no domain
    fi
    
    if echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

get_instance_metrics() {
    local instance_id="$1"
    
    if [ -z "$instance_id" ]; then
        echo "No instance ID provided"
        return 1
    fi
    
    # Get instance status
    local instance_state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown")
    
    echo "Instance State: $instance_state"
    
    # Get basic CloudWatch metrics if available
    local cpu_utilization=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 300 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "N/A")
    
    if [ "$cpu_utilization" != "N/A" ] && [ "$cpu_utilization" != "None" ]; then
        echo "CPU Utilization: ${cpu_utilization}%"
    fi
}

monitor_deployment() {
    local lb_dns="$1"
    local domain="$2"
    local continuous="${3:-false}"
    
    print_status "🔍 Starting OpenClaw deployment monitoring..."
    log "Starting monitoring for $lb_dns"
    
    while true; do
        echo ""
        echo "=============================="
        echo "Health Check - $(date)"
        echo "=============================="
        
        # Check load balancer health endpoint
        print_status "Checking load balancer health..."
        if check_health "http://$lb_dns"; then
            print_success "Load balancer health check passed"
            log "Load balancer health check: PASS"
        else
            print_error "Load balancer health check failed"
            log "Load balancer health check: FAIL"
        fi
        
        # Check OpenClaw Gateway
        print_status "Checking OpenClaw Gateway..."
        if check_openclaw_gateway "http://$lb_dns"; then
            print_success "OpenClaw Gateway is responding"
            log "OpenClaw Gateway check: PASS"
        else
            print_error "OpenClaw Gateway is not responding properly"
            log "OpenClaw Gateway check: FAIL"
        fi
        
        # Check SSL if domain provided
        if [ -n "$domain" ]; then
            print_status "Checking SSL certificate..."
            if check_ssl "$domain"; then
                print_success "SSL certificate is valid"
                log "SSL certificate check: PASS"
            else
                print_error "SSL certificate check failed"
                log "SSL certificate check: FAIL"
            fi
        fi
        
        # Get AWS instance information if available
        if command -v aws &> /dev/null; then
            print_status "Checking AWS instance metrics..."
            
            # Try to get instance ID from tags
            local instance_id=$(aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=openclaw-gateway" \
                          "Name=instance-state-name,Values=running" \
                --query 'Reservations[0].Instances[0].InstanceId' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                get_instance_metrics "$instance_id"
            else
                echo "Could not find OpenClaw instance"
            fi
        fi
        
        # Performance test
        print_status "Running performance test..."
        local response_time=$(curl -o /dev/null -s -w '%{time_total}' "http://$lb_dns/health" 2>/dev/null || echo "0")
        echo "Response time: ${response_time}s"
        log "Response time: ${response_time}s"
        
        # Check if continuous monitoring
        if [ "$continuous" != "true" ]; then
            break
        fi
        
        echo ""
        print_status "Next check in ${CHECK_INTERVAL} seconds... (Ctrl+C to stop)"
        sleep "$CHECK_INTERVAL"
    done
}

print_help() {
    echo "OpenClaw EC2 Deployment Monitor"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --continuous    Run continuous monitoring"
    echo "  -d, --domain DOMAIN Custom domain for SSL checks"
    echo "  -l, --lb-dns DNS    Load balancer DNS name"
    echo "  -i, --interval SEC  Check interval for continuous mode (default: 30)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # One-time health check"
    echo "  $0 -c                                # Continuous monitoring"
    echo "  $0 -d openclaw.example.com           # Include SSL checks"
    echo "  $0 -l my-lb-123456.us-east-1.elb.amazonaws.com"
}

# Parse command line arguments
CONTINUOUS=false
DOMAIN=""
LB_DNS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--continuous)
            CONTINUOUS=true
            shift
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -l|--lb-dns)
            LB_DNS="$2"
            shift 2
            ;;
        -i|--interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    # Get load balancer DNS if not provided
    if [ -z "$LB_DNS" ]; then
        LB_DNS=$(get_load_balancer_dns)
    fi
    
    if [ -z "$LB_DNS" ]; then
        print_error "Load balancer DNS is required"
        exit 1
    fi
    
    # Start monitoring
    monitor_deployment "$LB_DNS" "$DOMAIN" "$CONTINUOUS"
    
    echo ""
    print_success "Monitoring complete. Check $LOG_FILE for detailed logs."
}

# Run main function
main