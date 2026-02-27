#!/bin/bash
# OpenClaw EC2 Bootstrap Script - Proper Installation
# This script installs OpenClaw Gateway on Amazon Linux 2

set -euo pipefail

# Configuration from Terraform
OPENCLAW_PORT=${openclaw_port}
ENVIRONMENT=${environment}
AWS_REGION=${aws_region}
ANTHROPIC_API_KEY="${anthropic_api_key}"

# Logging
LOG_FILE="/var/log/openclaw-bootstrap.log"
exec 1> >(tee -a $LOG_FILE)
exec 2> >(tee -a $LOG_FILE >&2)

echo "Starting OpenClaw bootstrap at $(date)"
echo "Configuration: Port=$OPENCLAW_PORT, Env=$ENVIRONMENT, Region=$AWS_REGION"

# Update system
yum update -y

# Install required packages
yum install -y \
    curl \
    wget \
    git \
    htop \
    unzip \
    fail2ban \
    awscli

# Install Node.js 20 (LTS) - OpenClaw needs modern Node
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
yum install -y nodejs

echo "Node.js version: $(node --version)"
echo "NPM version: $(npm --version)"

# Create openclaw user
useradd -m -s /bin/bash openclaw
usermod -aG sudo openclaw

# Create directories
mkdir -p /var/log/openclaw
mkdir -p /home/openclaw/.openclaw
chown -R openclaw:openclaw /var/log/openclaw /home/openclaw/.openclaw

# Install OpenClaw CLI as openclaw user
echo "Installing OpenClaw CLI..."
sudo -u openclaw bash << 'EOF'
cd /home/openclaw

# Install OpenClaw CLI via npm
npm install -g openclaw

# Verify installation
openclaw --version

# Create workspace
mkdir -p /home/openclaw/.openclaw/workspace

# Create auth config with provided API key
mkdir -p /home/openclaw/.openclaw/agents/main/agent
cat > /home/openclaw/.openclaw/agents/main/agent/auth-profiles.json << AUTHEOF
{
  "version": 1,
  "profiles": {
    "anthropic:auto": {
      "type": "token",
      "provider": "anthropic",
      "token": "$ANTHROPIC_API_KEY"
    }
  },
  "lastGood": {
    "anthropic": "anthropic:auto"
  }
}
AUTHEOF

EOF

echo "OpenClaw CLI installed successfully"

# Create systemd service
cat > /etc/systemd/system/openclaw.service << 'EOF'
[Unit]
Description=OpenClaw Gateway
Documentation=https://docs.openclaw.ai
After=network.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/home/openclaw/.openclaw
Environment=PORT=8080
Environment=NODE_ENV=production
ExecStart=/usr/bin/openclaw gateway start --port 8080 --bind 0.0.0.0
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Performance settings
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Configure UFW firewall
yum install -y epel-release
yum install -y ufw

# Configure firewall to allow SSH and OpenClaw port
ufw --force enable
ufw allow ssh
ufw allow $OPENCLAW_PORT/tcp
ufw allow 80/tcp
ufw allow 443/tcp

# Configure fail2ban for security
systemctl enable fail2ban
systemctl start fail2ban

# Set up log rotation for OpenClaw
cat > /etc/logrotate.d/openclaw << 'EOF'
/var/log/openclaw/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 openclaw openclaw
    postrotate
        systemctl reload openclaw || true
    endscript
}
EOF

# Start OpenClaw service
systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw

echo "OpenClaw service started"

# Wait a moment for service to initialize
sleep 10

# Health check
echo "Performing health check..."
for i in {1..12}; do
    if curl -f http://localhost:$OPENCLAW_PORT/ >/dev/null 2>&1; then
        echo "✅ OpenClaw Gateway is responding on port $OPENCLAW_PORT"
        break
    else
        echo "⏳ Waiting for OpenClaw Gateway to start... (attempt $i/12)"
        sleep 10
    fi
done

# Final status
systemctl status openclaw --no-pager
echo "OpenClaw Gateway bootstrap completed at $(date)"
echo "Service accessible at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):$OPENCLAW_PORT"