#!/bin/bash
# OpenClaw EC2 Bootstrap Script
# This script sets up and runs OpenClaw Gateway on Amazon Linux 2

set -euo pipefail

# Configuration from Terraform
OPENCLAW_PORT=${openclaw_port}
OPENCLAW_VERSION=${openclaw_version}
ENVIRONMENT=${environment}
AWS_REGION=${aws_region}

# Logging
LOG_FILE="/var/log/openclaw-bootstrap.log"
exec 1> >(tee -a $LOG_FILE)
exec 2> >(tee -a $LOG_FILE >&2)

echo "Starting OpenClaw bootstrap at $(date)"
echo "Configuration: Port=$OPENCLAW_PORT, Version=$OPENCLAW_VERSION, Env=$ENVIRONMENT, Region=$AWS_REGION"

# Update system
yum update -y

# Install required packages
yum install -y \
    docker \
    git \
    htop \
    curl \
    wget \
    unzip \
    fail2ban \
    nginx \
    awscli

# Install Node.js 18 (LTS)
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
yum install -y nodejs

# Install PM2 globally
npm install -g pm2

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Create openclaw user
useradd -m -s /bin/bash openclaw
usermod -aG docker openclaw

# Create directories
mkdir -p /opt/openclaw
mkdir -p /var/log/openclaw
mkdir -p /etc/openclaw

# Set ownership
chown -R openclaw:openclaw /opt/openclaw /var/log/openclaw /etc/openclaw

# Configure CloudWatch Agent (if monitoring enabled)
if [ "${ENVIRONMENT}" != "dev" ]; then
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    rpm -U ./amazon-cloudwatch-agent.rpm
    
    # Create CloudWatch agent config
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/openclaw/gateway.log",
                        "log_group_name": "/aws/ec2/openclaw-${ENVIRONMENT}",
                        "log_stream_name": "{instance_id}/openclaw-gateway",
                        "timestamp_format": "%Y-%m-%d %H:%M:%S"
                    },
                    {
                        "file_path": "/var/log/openclaw-bootstrap.log",
                        "log_group_name": "/aws/ec2/openclaw-${ENVIRONMENT}",
                        "log_stream_name": "{instance_id}/bootstrap",
                        "timestamp_format": "%Y-%m-%d %H:%M:%S"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "OpenClaw/$ENVIRONMENT",
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
    }
}
EOF

    # Start CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -s \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
fi

# Install OpenClaw Gateway
echo "Installing OpenClaw Gateway..."
cd /opt/openclaw

# Clone or download OpenClaw (placeholder - adjust based on actual installation method)
if [ "$OPENCLAW_VERSION" = "latest" ]; then
    # For now, create a simple Node.js app that simulates OpenClaw Gateway
    cat > app.js << 'EOF'
const express = require('express');
const app = express();

const PORT = process.env.PORT || 3000;
const ENVIRONMENT = process.env.ENVIRONMENT || 'dev';

// Middleware
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        environment: ENVIRONMENT,
        port: PORT,
        uptime: process.uptime()
    });
});

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        message: 'OpenClaw Gateway',
        version: '1.0.0',
        environment: ENVIRONMENT,
        timestamp: new Date().toISOString()
    });
});

// API endpoint placeholder
app.get('/api/status', (req, res) => {
    res.json({
        api: 'OpenClaw Gateway API',
        status: 'running',
        environment: ENVIRONMENT,
        timestamp: new Date().toISOString()
    });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`OpenClaw Gateway listening on port $${PORT}`);
    console.log(`Environment: $${ENVIRONMENT}`);
    console.log(`Health check: http://localhost:$${PORT}/health`);
});
EOF

    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "openclaw-gateway",
  "version": "1.0.0",
  "description": "OpenClaw Gateway Service",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "dev": "nodemon app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "keywords": ["openclaw", "gateway", "api"],
  "author": "OpenClaw",
  "license": "MIT"
}
EOF

    # Install dependencies
    npm install
else
    # Handle specific versions here
    echo "Specific version deployment not implemented yet: $OPENCLAW_VERSION"
fi

# Set ownership
chown -R openclaw:openclaw /opt/openclaw

# Create PM2 ecosystem file
cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'openclaw-gateway',
    script: '/opt/openclaw/app.js',
    user: 'openclaw',
    cwd: '/opt/openclaw',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: $OPENCLAW_PORT,
      ENVIRONMENT: '$ENVIRONMENT',
      AWS_REGION: '$AWS_REGION'
    },
    log_file: '/var/log/openclaw/combined.log',
    out_file: '/var/log/openclaw/out.log',
    error_file: '/var/log/openclaw/error.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
EOF

chown openclaw:openclaw ecosystem.config.js

# Configure Nginx as reverse proxy
cat > /etc/nginx/conf.d/openclaw.conf << EOF
server {
    listen 80;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Health check endpoint (direct access)
    location /health {
        proxy_pass http://localhost:$OPENCLAW_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Main application
    location / {
        proxy_pass http://localhost:$OPENCLAW_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeout settings
        proxy_connect_timeout       60s;
        proxy_send_timeout          60s;
        proxy_read_timeout          60s;
    }
    
    # Nginx status for monitoring
    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
    }
}
EOF

# Test nginx configuration
nginx -t

# Start and enable nginx
systemctl start nginx
systemctl enable nginx

# Configure fail2ban
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
EOF

systemctl start fail2ban
systemctl enable fail2ban

# Start OpenClaw with PM2 as openclaw user
echo "Starting OpenClaw Gateway with PM2..."
sudo -u openclaw bash << EOF
cd /opt/openclaw
pm2 start ecosystem.config.js
pm2 save
pm2 startup systemd -u openclaw --hp /home/openclaw
EOF

# Install PM2 startup script
env PATH=\$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u openclaw --hp /home/openclaw

# Wait for application to start
echo "Waiting for OpenClaw Gateway to start..."
sleep 30

# Verify application is running
for i in {1..10}; do
    if curl -f http://localhost:$OPENCLAW_PORT/health >/dev/null 2>&1; then
        echo "OpenClaw Gateway is running successfully!"
        break
    fi
    echo "Attempt $i/10: Waiting for application..."
    sleep 10
done

# Final health check
if curl -f http://localhost:$OPENCLAW_PORT/health >/dev/null 2>&1; then
    echo "Bootstrap completed successfully at $(date)"
    echo "OpenClaw Gateway is available at http://localhost:$OPENCLAW_PORT"
    echo "Health check: http://localhost:$OPENCLAW_PORT/health"
else
    echo "ERROR: OpenClaw Gateway failed to start properly"
    echo "Check logs: /var/log/openclaw/"
    exit 1
fi

# Set up log rotation
cat > /etc/logrotate.d/openclaw << EOF
/var/log/openclaw/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
    su openclaw openclaw
}
EOF

echo "OpenClaw EC2 bootstrap completed successfully!"