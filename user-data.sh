#!/bin/bash
# OpenClaw EC2 User Data Script
# Addresses user data script size limits and installation issues

set -e  # Exit on any error

# Logging setup
LOG_FILE="/var/log/openclaw-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "$(date): Starting OpenClaw setup on $(hostname)"

# Template variables (filled by Terraform)
OPENCLAW_PORT="${openclaw_port}"
OPENCLAW_VERSION="${openclaw_version}"
PROJECT_NAME="${project_name}"
ENVIRONMENT="${environment}"
AWS_REGION="${aws_region}"

# System updates and basic packages
echo "$(date): Updating system packages..."
yum update -y

# Install required packages
yum install -y \
    docker \
    awscli \
    amazon-cloudwatch-agent \
    amazon-ssm-agent \
    curl \
    wget \
    unzip \
    jq \
    htop \
    git

# Start and enable services
systemctl start docker
systemctl enable docker
systemctl start amazon-ssm-agent
systemctl enable amazon-ssm-agent

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Docker Compose
echo "$(date): Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
APP_DIR="/opt/openclaw"
mkdir -p $APP_DIR
cd $APP_DIR

# Create OpenClaw configuration
echo "$(date): Creating OpenClaw configuration..."
cat > docker-compose.yml << EOF
version: '3.8'
services:
  openclaw:
    image: openclaw/openclaw:$OPENCLAW_VERSION
    ports:
      - "$OPENCLAW_PORT:3000"
    environment:
      - NODE_ENV=production
      - PORT=3000
      - AWS_REGION=$AWS_REGION
      - PROJECT_NAME=$PROJECT_NAME
      - ENVIRONMENT=$ENVIRONMENT
    volumes:
      - /opt/openclaw/data:/app/data
      - /opt/openclaw/logs:/app/logs
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "awslogs"
      options:
        awslogs-group: "/aws/ec2/$PROJECT_NAME-$ENVIRONMENT"
        awslogs-region: "$AWS_REGION"
        awslogs-stream: "openclaw-\$(hostname)"
EOF

# Create data and logs directories
mkdir -p /opt/openclaw/data /opt/openclaw/logs
chown -R ec2-user:ec2-user /opt/openclaw

# Configure CloudWatch Agent
echo "$(date): Configuring CloudWatch Agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "metrics": {
        "namespace": "OpenClaw/$PROJECT_NAME/$ENVIRONMENT",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/opt/openclaw/logs/*.log",
                        "log_group_name": "/aws/ec2/$PROJECT_NAME-$ENVIRONMENT",
                        "log_stream_name": "openclaw-app-{instance_id}"
                    },
                    {
                        "file_path": "/var/log/openclaw-setup.log",
                        "log_group_name": "/aws/ec2/$PROJECT_NAME-$ENVIRONMENT",
                        "log_stream_name": "setup-{instance_id}"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Pull and start OpenClaw
echo "$(date): Pulling and starting OpenClaw..."
cd /opt/openclaw
docker-compose pull
docker-compose up -d

# Wait for service to be ready
echo "$(date): Waiting for OpenClaw to be ready..."
RETRY_COUNT=0
MAX_RETRIES=30

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f http://localhost:$OPENCLAW_PORT/health > /dev/null 2>&1; then
        echo "$(date): OpenClaw is ready!"
        break
    fi
    
    echo "$(date): Waiting for OpenClaw... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "$(date): ERROR: OpenClaw failed to start after $MAX_RETRIES attempts"
    exit 1
fi

# Create systemd service for auto-restart
cat > /etc/systemd/system/openclaw.service << EOF
[Unit]
Description=OpenClaw Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/openclaw
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw.service

# Setup log rotation
cat > /etc/logrotate.d/openclaw << EOF
/opt/openclaw/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 ec2-user ec2-user
    postrotate
        docker-compose -f /opt/openclaw/docker-compose.yml restart openclaw
    endscript
}
EOF

# Create health check script
cat > /opt/openclaw/health-check.sh << 'EOF'
#!/bin/bash
# Health check script for OpenClaw

HEALTH_URL="http://localhost:${OPENCLAW_PORT}/health"
MAX_ATTEMPTS=3
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    if curl -sf "$HEALTH_URL" > /dev/null; then
        echo "Health check passed"
        exit 0
    fi
    
    echo "Health check failed (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    ATTEMPT=$((ATTEMPT + 1))
    sleep 5
done

echo "Health check failed after $MAX_ATTEMPTS attempts"
exit 1
EOF

chmod +x /opt/openclaw/health-check.sh

# Setup cron job for health monitoring
echo "*/5 * * * * /opt/openclaw/health-check.sh >> /var/log/openclaw-health.log 2>&1" | crontab -

# Signal completion to CloudFormation/Auto Scaling
echo "$(date): OpenClaw setup completed successfully"

# Send success signal to Auto Scaling (if lifecycle hook exists)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
ASG_NAME=$(aws ec2 describe-tags --region $AWS_REGION --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=aws:autoscaling:groupName" --query "Tags[0].Value" --output text 2>/dev/null || echo "")

if [ -n "$ASG_NAME" ] && [ "$ASG_NAME" != "None" ]; then
    echo "$(date): Sending ready signal to Auto Scaling Group: $ASG_NAME"
    aws autoscaling complete-lifecycle-action \
        --region $AWS_REGION \
        --lifecycle-hook-name "graceful-shutdown" \
        --auto-scaling-group-name "$ASG_NAME" \
        --instance-id "$INSTANCE_ID" \
        --lifecycle-action-result CONTINUE || true
fi

echo "$(date): Setup script completed"
EOF