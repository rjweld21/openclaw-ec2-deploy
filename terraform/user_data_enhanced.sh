#!/bin/bash

# Enhanced user_data.sh - Full OpenClaw installation
# Logs everything to /var/log/openclaw-install.log

exec > >(tee -a /var/log/openclaw-install.log) 2>&1

echo "=== OpenClaw EC2 Installation Started: $(date) ==="

# Update system
echo "📦 Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install essential packages
echo "📦 Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    htop \
    unzip \
    vim \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    python3 \
    python3-pip \
    systemd

# Install Docker
echo "🐳 Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install Node.js (LTS)
echo "📦 Installing Node.js LTS..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Verify Node.js installation
node --version
npm --version

# Install PM2 globally
echo "📦 Installing PM2..."
npm install -g pm2

# Install AWS CLI
echo "☁️ Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create openclaw user
echo "👤 Creating OpenClaw user..."
useradd -m -s /bin/bash openclaw
usermod -aG sudo openclaw
usermod -aG docker openclaw

# Set up SSH keys
echo "🔐 Setting up SSH keys..."
mkdir -p /home/ubuntu/.ssh
chown -R ubuntu:ubuntu /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh

mkdir -p /home/openclaw/.ssh
chown -R openclaw:openclaw /home/openclaw/.ssh
chmod 700 /home/openclaw/.ssh
chmod 600 /home/openclaw/.ssh/authorized_keys

# Enable and start services
echo "🚀 Starting services..."
systemctl enable docker
systemctl start docker

# Create OpenClaw directory structure
echo "📁 Setting up OpenClaw directories..."
mkdir -p /opt/openclaw
mkdir -p /opt/openclaw/logs
mkdir -p /opt/openclaw/data
mkdir -p /opt/openclaw/config
chown -R openclaw:openclaw /opt/openclaw

# Install OpenClaw
echo "🌐 Installing OpenClaw..."
su - openclaw -c "
cd /opt/openclaw

# Install OpenClaw globally
npm install -g openclaw

# Create OpenClaw config directory in user home
mkdir -p ~/.openclaw

# Create basic OpenClaw configuration
cat > ~/.openclaw/config.json << 'CONFIG_EOF'
{
  \"server\": {
    \"port\": 8080,
    \"host\": \"0.0.0.0\"
  },
  \"gateway\": {
    \"enabled\": true,
    \"port\": 8080,
    \"cors\": {
      \"enabled\": true,
      \"origin\": \"*\"
    }
  },
  \"anthropic\": {
    \"api_key\": \"${anthropic_api_key}\"
  },
  \"logging\": {
    \"level\": \"info\",
    \"file\": \"/opt/openclaw/logs/openclaw.log\"
  },
  \"workspace\": \"/opt/openclaw/data\"
}
CONFIG_EOF

# Initialize OpenClaw workspace
echo '📂 Initializing OpenClaw workspace...'
mkdir -p /opt/openclaw/data

# Create PM2 ecosystem file
cat > /opt/openclaw/ecosystem.config.js << 'PM2_EOF'
module.exports = {
  apps: [
    {
      name: 'openclaw-gateway',
      script: 'openclaw',
      args: 'gateway start',
      cwd: '/opt/openclaw',
      env: {
        NODE_ENV: 'production',
        OPENCLAW_CONFIG: '/home/openclaw/.openclaw/config.json',
        ANTHROPIC_API_KEY: '${anthropic_api_key}',
        PORT: '8080'
      },
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      log_file: '/opt/openclaw/logs/openclaw-combined.log',
      out_file: '/opt/openclaw/logs/openclaw-out.log',
      error_file: '/opt/openclaw/logs/openclaw-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
    },
    {
      name: 'health-check',
      script: '/opt/openclaw/health-check.js',
      cwd: '/opt/openclaw',
      env: {
        PORT: '8081'
      },
      instances: 1,
      autorestart: true,
      watch: false
    }
  ]
};
PM2_EOF

echo '✅ OpenClaw installation completed'
"

# Create health check endpoint (secondary port for diagnostics)
echo "🏥 Setting up health check endpoint..."
cat > /opt/openclaw/health-check.js << 'EOF'
const http = require('http');
const { exec } = require('child_process');

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }
  
  if (url.pathname === '/health') {
    // Check if OpenClaw process is running
    exec('pm2 list | grep openclaw-gateway', (error, stdout, stderr) => {
      const openclawRunning = !error && stdout.includes('online');
      
      const health = {
        status: openclawRunning ? 'healthy' : 'degraded',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        services: {
          healthCheck: 'online',
          openclawGateway: openclawRunning ? 'online' : 'offline'
        },
        system: {
          nodeVersion: process.version,
          platform: process.platform,
          arch: process.arch,
          memory: process.memoryUsage()
        }
      };
      
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(health, null, 2));
    });
  } else if (url.pathname === '/status') {
    // More detailed status
    exec('pm2 jlist', (error, stdout, stderr) => {
      const status = {
        timestamp: new Date().toISOString(),
        pm2Processes: error ? 'error' : JSON.parse(stdout),
        error: error ? error.message : null
      };
      
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(status, null, 2));
    });
  } else {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>OpenClaw EC2 Instance</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .status { padding: 20px; margin: 10px 0; border-radius: 5px; }
            .healthy { background-color: #d4edda; color: #155724; }
            .degraded { background-color: #f8d7da; color: #721c24; }
          </style>
        </head>
        <body>
          <h1>🌐 OpenClaw EC2 Instance</h1>
          <div id="status" class="status">Loading status...</div>
          <h2>Quick Links</h2>
          <ul>
            <li><a href="/health">Health Check (JSON)</a></li>
            <li><a href="/status">Detailed Status (JSON)</a></li>
            <li><a href="http://${req.headers.host.split(':')[0]}:8080">OpenClaw Gateway</a></li>
          </ul>
          <p><strong>Instance Info:</strong></p>
          <ul>
            <li>Timestamp: ${new Date().toISOString()}</li>
            <li>Uptime: ${Math.floor(process.uptime())} seconds</li>
            <li>Node.js: ${process.version}</li>
          </ul>
          
          <script>
            fetch('/health')
              .then(r => r.json())
              .then(data => {
                const div = document.getElementById('status');
                div.className = 'status ' + data.status;
                div.innerHTML = '<strong>Status:</strong> ' + data.status + 
                  '<br><strong>OpenClaw Gateway:</strong> ' + data.services.openclawGateway;
              })
              .catch(e => {
                document.getElementById('status').innerHTML = 'Error loading status: ' + e.message;
              });
          </script>
        </body>
      </html>
    `);
  }
});

const port = process.env.PORT || 8081;
server.listen(port, '0.0.0.0', () => {
  console.log(`Health check server running on port ${port}`);
});
EOF

chown openclaw:openclaw /opt/openclaw/health-check.js
chmod +x /opt/openclaw/health-check.js

# Start OpenClaw services with PM2
echo "🚀 Starting OpenClaw services..."
su - openclaw -c "
cd /opt/openclaw

# Start services using PM2 ecosystem file  
pm2 start ecosystem.config.js

# Set up PM2 to start on boot
pm2 startup systemd -u openclaw --hp /home/openclaw
pm2 save

echo 'Services started:'
pm2 list
pm2 logs --lines 10
"

# Create OpenClaw systemd service (backup/alternative to PM2)
echo "📋 Creating systemd service..."
cat > /etc/systemd/system/openclaw.service << 'SYSTEMD_EOF'
[Unit]
Description=OpenClaw Gateway Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/opt/openclaw
ExecStart=/usr/bin/npm exec openclaw gateway start
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=OPENCLAW_CONFIG=/home/openclaw/.openclaw/config.json
Environment=PORT=8080

# Output to journal
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

# Enable the service (but don't start it since PM2 is handling it)
systemctl daemon-reload
systemctl enable openclaw.service

# Set up log rotation
echo "📝 Setting up log rotation..."
cat > /etc/logrotate.d/openclaw << 'LOGROTATE_EOF'
/opt/openclaw/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 openclaw openclaw
    postrotate
        sudo -u openclaw pm2 reloadLogs
    endscript
}
LOGROTATE_EOF

# Create validation script
echo "✅ Creating validation script..."
cat > /opt/openclaw/validate-installation.sh << 'VALIDATION_EOF'
#!/bin/bash

echo "🔍 OpenClaw Installation Validation"
echo "=================================="

# Check if openclaw command is available
echo "1. Checking OpenClaw command..."
if command -v openclaw &> /dev/null; then
    echo "   ✅ OpenClaw command found: $(which openclaw)"
    openclaw --version 2>/dev/null || echo "   ⚠️ Version check failed"
else
    echo "   ❌ OpenClaw command not found"
fi

# Check PM2 processes
echo "2. Checking PM2 processes..."
PM2_OUTPUT=$(pm2 jlist 2>/dev/null)
if echo "$PM2_OUTPUT" | jq -e '.[] | select(.name == "openclaw-gateway")' &>/dev/null; then
    echo "   ✅ OpenClaw Gateway process running"
else
    echo "   ❌ OpenClaw Gateway process not found"
fi

if echo "$PM2_OUTPUT" | jq -e '.[] | select(.name == "health-check")' &>/dev/null; then
    echo "   ✅ Health check process running"
else
    echo "   ❌ Health check process not found"
fi

# Check ports
echo "3. Checking port availability..."
if netstat -tuln | grep -q ":8080 "; then
    echo "   ✅ Port 8080 is open (OpenClaw Gateway)"
else
    echo "   ❌ Port 8080 is not open"
fi

if netstat -tuln | grep -q ":8081 "; then
    echo "   ✅ Port 8081 is open (Health Check)"
else
    echo "   ❌ Port 8081 is not open"
fi

# Check HTTP endpoints
echo "4. Testing HTTP endpoints..."
if curl -sf localhost:8080/health &>/dev/null || curl -sf localhost:8080/ &>/dev/null; then
    echo "   ✅ OpenClaw Gateway responding on port 8080"
else
    echo "   ❌ OpenClaw Gateway not responding on port 8080"
fi

if curl -sf localhost:8081/health &>/dev/null; then
    echo "   ✅ Health check responding on port 8081"
else
    echo "   ❌ Health check not responding on port 8081"
fi

# Check logs
echo "5. Checking logs..."
if [ -f "/opt/openclaw/logs/openclaw-combined.log" ]; then
    echo "   ✅ OpenClaw logs found"
    echo "   📝 Last 5 log lines:"
    tail -5 /opt/openclaw/logs/openclaw-combined.log | sed 's/^/      /'
else
    echo "   ⚠️ OpenClaw logs not found"
fi

echo ""
echo "🔗 Access Information:"
echo "   - OpenClaw Gateway: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "   - Health Check: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo ""
VALIDATION_EOF

chmod +x /opt/openclaw/validate-installation.sh
chown openclaw:openclaw /opt/openclaw/validate-installation.sh

# Wait a moment for services to start
echo "⏳ Waiting for services to stabilize..."
sleep 30

# Run validation
echo "🔍 Running installation validation..."
su - openclaw -c "/opt/openclaw/validate-installation.sh"

# Final status
echo ""
echo "=== OpenClaw EC2 Installation Summary ==="
echo "Installation completed at: $(date)"
echo "OpenClaw Gateway: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "Health Check: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo "Validation script: /opt/openclaw/validate-installation.sh"
echo "Logs directory: /opt/openclaw/logs/"
echo "Config file: /home/openclaw/.openclaw/config.json"
echo "PM2 status: su - openclaw -c 'pm2 status'"

# Log completion
echo "✅ EC2 OpenClaw installation completed successfully at $(date)" | tee -a /var/log/openclaw-install.log
EOF