#!/bin/bash
# OpenClaw Gateway EC2 Bootstrap Script
# Installs and configures OpenClaw Gateway with production settings

set -e

# Logging
exec > >(tee /var/log/openclaw-bootstrap.log)
exec 2>&1

echo "Starting OpenClaw Gateway bootstrap at $(date)"

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    htop \
    unzip \
    nginx \
    certbot \
    python3-certbot-nginx \
    fail2ban \
    ufw

# Install Node.js 18 (LTS)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install PM2 globally
npm install -g pm2

# Install AWS CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Create openclaw user
useradd -m -s /bin/bash openclaw
usermod -aG sudo openclaw

# Create directories
mkdir -p /opt/openclaw
mkdir -p /var/log/openclaw
mkdir -p /etc/openclaw
chown -R openclaw:openclaw /opt/openclaw /var/log/openclaw /etc/openclaw

# Install OpenClaw Gateway
cd /opt/openclaw
sudo -u openclaw npm install -g openclaw

# Create OpenClaw configuration
cat > /etc/openclaw/config.json << 'EOF'
{
  "gateway": {
    "port": 18789,
    "bind": "0.0.0.0",
    "auth": {
      "mode": "token",
      "token": "REPLACE_WITH_SECURE_TOKEN"
    },
    "controlUi": {
      "enabled": true,
      "basePath": "/ui"
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-3-5-sonnet-20241022"
      }
    }
  },
  "logging": {
    "level": "info",
    "file": "/var/log/openclaw/gateway.log"
  }
}
EOF

chown openclaw:openclaw /etc/openclaw/config.json
chmod 600 /etc/openclaw/config.json

# Create PM2 ecosystem file
cat > /opt/openclaw/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'openclaw-gateway',
    script: 'openclaw',
    args: 'gateway --config /etc/openclaw/config.json',
    instances: 1,
    exec_mode: 'fork',
    user: 'openclaw',
    cwd: '/opt/openclaw',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '/var/log/openclaw/pm2-error.log',
    out_file: '/var/log/openclaw/pm2-out.log',
    log_file: '/var/log/openclaw/pm2.log',
    time: true,
    max_restarts: 10,
    restart_delay: 5000,
    watch: false,
    ignore_watch: ["node_modules", "logs"],
    max_memory_restart: '512M'
  }]
};
EOF

chown openclaw:openclaw /opt/openclaw/ecosystem.config.js

# Configure Nginx reverse proxy
cat > /etc/nginx/sites-available/openclaw << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Proxy to OpenClaw Gateway
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }
}
EOF

# Enable Nginx site
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# Configure UFW firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable

# Configure fail2ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
EOF

systemctl restart fail2ban

# Configure CloudWatch Agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/openclaw/gateway.log",
                        "log_group_name": "openclaw-gateway",
                        "log_stream_name": "{instance_id}/gateway.log"
                    },
                    {
                        "file_path": "/var/log/openclaw/pm2.log",
                        "log_group_name": "openclaw-gateway",
                        "log_stream_name": "{instance_id}/pm2.log"
                    },
                    {
                        "file_path": "/var/log/nginx/access.log",
                        "log_group_name": "openclaw-gateway",
                        "log_stream_name": "{instance_id}/nginx-access.log"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "OpenClaw/Gateway",
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

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Start PM2 as openclaw user and save configuration
sudo -u openclaw bash << 'EOF'
cd /opt/openclaw
pm2 start ecosystem.config.js
pm2 save
pm2 startup systemd -u openclaw --hp /home/openclaw
EOF

# Enable PM2 startup script
env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u openclaw --hp /home/openclaw

# Create backup script
cat > /usr/local/bin/openclaw-backup.sh << 'EOF'
#!/bin/bash
# OpenClaw backup script

BACKUP_DIR="/opt/openclaw-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="openclaw_backup_$DATE.tar.gz"

mkdir -p $BACKUP_DIR

# Backup OpenClaw data and config
tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
    /etc/openclaw \
    /home/openclaw/.openclaw \
    /var/log/openclaw

# Keep only last 7 backups
find $BACKUP_DIR -name "openclaw_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
EOF

chmod +x /usr/local/bin/openclaw-backup.sh

# Add backup cron job
echo "0 2 * * * root /usr/local/bin/openclaw-backup.sh" >> /etc/crontab

# Create health check script
cat > /usr/local/bin/openclaw-health.sh << 'EOF'
#!/bin/bash
# OpenClaw health check script

HEALTH_URL="http://localhost:18789/"
TIMEOUT=10

if curl -f -s --max-time $TIMEOUT "$HEALTH_URL" > /dev/null; then
    echo "OpenClaw Gateway is healthy"
    exit 0
else
    echo "OpenClaw Gateway is unhealthy - restarting"
    sudo -u openclaw pm2 restart openclaw-gateway
    exit 1
fi
EOF

chmod +x /usr/local/bin/openclaw-health.sh

# Add health check cron job (every 5 minutes)
echo "*/5 * * * * root /usr/local/bin/openclaw-health.sh" >> /etc/crontab

# Set up log rotation
cat > /etc/logrotate.d/openclaw << 'EOF'
/var/log/openclaw/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

# Enable services
systemctl enable nginx
systemctl enable fail2ban
systemctl enable amazon-cloudwatch-agent

# Final permissions
chown -R openclaw:openclaw /opt/openclaw /var/log/openclaw
chmod -R 755 /opt/openclaw
chmod -R 644 /var/log/openclaw

echo "OpenClaw Gateway bootstrap completed successfully at $(date)"
echo "Gateway should be accessible on port 18789"
echo "Nginx reverse proxy is running on ports 80/443"
echo "PM2 is managing the OpenClaw process"
echo "CloudWatch logging is configured"
echo "Automated backups are scheduled daily at 2 AM"
echo "Health checks run every 5 minutes"

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource AutoScalingGroup --region ${aws_region} || true