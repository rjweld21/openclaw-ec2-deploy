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

# Install OpenClaw Gateway with React Frontend
echo "Installing OpenClaw Gateway with React Frontend..."
cd /opt/openclaw

# Create full-stack OpenClaw application
if [ "$OPENCLAW_VERSION" = "latest" ]; then
    # Create React frontend structure
    mkdir -p frontend/src frontend/public
    
    # Create package.json for React frontend
    cat > frontend/package.json << 'EOF'
{
  "name": "openclaw-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@testing-library/jest-dom": "^5.16.4",
    "@testing-library/react": "^13.3.0",
    "@testing-library/user-event": "^13.5.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.3.0",
    "react-scripts": "5.0.1",
    "web-vitals": "^2.1.4"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "homepage": "."
}
EOF

    # Create React App.js
    cat > frontend/src/App.js << 'EOF'
import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchStatus();
  }, []);

  const fetchStatus = async () => {
    try {
      const response = await fetch('/api/status');
      const data = await response.json();
      setStatus(data);
    } catch (err) {
      setError('Failed to fetch status');
      console.error('Error:', err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <div className="logo">
          <h1>🦾 OpenClaw Gateway</h1>
          <p>Your AI-Powered Assistant Platform</p>
        </div>
        
        <div className="status-card">
          <h2>System Status</h2>
          {loading && <div className="loading">Loading...</div>}
          {error && <div className="error">{error}</div>}
          {status && (
            <div className="status-info">
              <div className="status-item">
                <strong>API Status:</strong> 
                <span className="status-healthy">{status.status}</span>
              </div>
              <div className="status-item">
                <strong>Environment:</strong> {status.environment}
              </div>
              <div className="status-item">
                <strong>Last Updated:</strong> {new Date(status.timestamp).toLocaleString()}
              </div>
            </div>
          )}
        </div>

        <div className="features">
          <h2>Features</h2>
          <div className="feature-grid">
            <div className="feature">
              <h3>🤖 AI Assistant</h3>
              <p>Intelligent conversation and task automation</p>
            </div>
            <div className="feature">
              <h3>🌐 Web Integration</h3>
              <p>Connect with websites and online services</p>
            </div>
            <div className="feature">
              <h3>📱 Cross-Platform</h3>
              <p>Works on desktop, mobile, and web</p>
            </div>
            <div className="feature">
              <h3>🔒 Secure</h3>
              <p>Enterprise-grade security and privacy</p>
            </div>
          </div>
        </div>

        <div className="actions">
          <button onClick={fetchStatus} className="refresh-btn">
            Refresh Status
          </button>
        </div>
      </header>
    </div>
  );
}

export default App;
EOF

    # Create React App.css
    cat > frontend/src/App.css << 'EOF'
.App {
  text-align: center;
  min-height: 100vh;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
    sans-serif;
}

.App-header {
  padding: 20px;
  max-width: 1200px;
  margin: 0 auto;
}

.logo h1 {
  font-size: 3.5rem;
  margin: 20px 0 10px 0;
  text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
}

.logo p {
  font-size: 1.3rem;
  margin-bottom: 40px;
  opacity: 0.9;
}

.status-card {
  background: rgba(255, 255, 255, 0.1);
  border-radius: 15px;
  padding: 30px;
  margin: 30px auto;
  max-width: 600px;
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.2);
}

.status-card h2 {
  margin-top: 0;
  font-size: 1.8rem;
}

.status-info {
  text-align: left;
  margin: 20px 0;
}

.status-item {
  margin: 15px 0;
  font-size: 1.1rem;
}

.status-item strong {
  display: inline-block;
  width: 140px;
}

.status-healthy {
  color: #4ade80;
  font-weight: bold;
  text-transform: uppercase;
}

.loading {
  font-size: 1.1rem;
  opacity: 0.8;
  animation: pulse 1.5s ease-in-out infinite alternate;
}

@keyframes pulse {
  from { opacity: 0.6; }
  to { opacity: 1; }
}

.error {
  color: #ef4444;
  font-weight: bold;
  padding: 10px;
  background: rgba(239, 68, 68, 0.1);
  border-radius: 8px;
}

.features {
  margin: 50px 0;
}

.features h2 {
  font-size: 2.2rem;
  margin-bottom: 30px;
}

.feature-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 25px;
  margin: 30px 0;
}

.feature {
  background: rgba(255, 255, 255, 0.1);
  padding: 25px;
  border-radius: 12px;
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.2);
  transition: transform 0.3s ease, box-shadow 0.3s ease;
}

.feature:hover {
  transform: translateY(-5px);
  box-shadow: 0 10px 25px rgba(0,0,0,0.2);
}

.feature h3 {
  margin: 0 0 15px 0;
  font-size: 1.3rem;
}

.feature p {
  margin: 0;
  opacity: 0.9;
  line-height: 1.5;
}

.actions {
  margin: 40px 0;
}

.refresh-btn {
  background: rgba(255, 255, 255, 0.2);
  color: white;
  border: 2px solid rgba(255, 255, 255, 0.3);
  padding: 12px 30px;
  font-size: 1.1rem;
  border-radius: 25px;
  cursor: pointer;
  transition: all 0.3s ease;
  backdrop-filter: blur(10px);
}

.refresh-btn:hover {
  background: rgba(255, 255, 255, 0.3);
  border-color: rgba(255, 255, 255, 0.5);
  transform: scale(1.05);
}

@media (max-width: 768px) {
  .logo h1 {
    font-size: 2.5rem;
  }
  
  .feature-grid {
    grid-template-columns: 1fr;
  }
  
  .status-card {
    margin: 20px;
    padding: 20px;
  }
}
EOF

    # Create React index.js
    cat > frontend/src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

    # Create index.css
    cat > frontend/src/index.css << 'EOF'
body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
    sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

code {
  font-family: source-code-pro, Menlo, Monaco, Consolas, 'Courier New',
    monospace;
}

* {
  box-sizing: border-box;
}
EOF

    # Create public/index.html
    cat > frontend/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <link rel="icon" href="%PUBLIC_URL%/favicon.ico" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta
      name="description"
      content="OpenClaw Gateway - Your AI-Powered Assistant Platform"
    />
    <title>OpenClaw Gateway</title>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
EOF

    # Create a simple favicon
    echo "" > frontend/public/favicon.ico

    # Build React frontend
    cd /opt/openclaw/frontend
    npm install
    npm run build
    
    # Move build files to serve directory
    cd /opt/openclaw
    mkdir -p public
    cp -r frontend/build/* public/
    
    # Create Express server that serves React app and API
    cat > app.js << 'EOF'
const express = require('express');
const path = require('path');
const app = express();

const PORT = process.env.PORT || 3000;
const ENVIRONMENT = process.env.ENVIRONMENT || 'dev';

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Serve static React build files
app.use(express.static(path.join(__dirname, 'public')));

// API Routes
app.get('/api/status', (req, res) => {
    res.json({
        api: 'OpenClaw Gateway API',
        status: 'running',
        environment: ENVIRONMENT,
        timestamp: new Date().toISOString(),
        version: '1.0.0',
        uptime: process.uptime()
    });
});

// Health check endpoint (for load balancer)
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        environment: ENVIRONMENT,
        port: PORT,
        uptime: process.uptime(),
        version: '1.0.0'
    });
});

// Additional API endpoints
app.get('/api/info', (req, res) => {
    res.json({
        name: 'OpenClaw Gateway',
        version: '1.0.0',
        environment: ENVIRONMENT,
        features: [
            'AI Assistant',
            'Web Integration', 
            'Cross-Platform',
            'Secure'
        ],
        endpoints: {
            health: '/health',
            status: '/api/status',
            info: '/api/info'
        }
    });
});

// Serve React app for all non-API routes (SPA routing)
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ 
        error: 'Something went wrong!',
        environment: ENVIRONMENT,
        timestamp: new Date().toISOString()
    });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`OpenClaw Gateway listening on port ${PORT}`);
    console.log(`Environment: ${ENVIRONMENT}`);
    console.log(`Health check: http://localhost:${PORT}/health`);
    console.log(`React app: http://localhost:${PORT}`);
    console.log(`API endpoints: http://localhost:${PORT}/api/*`);
});
EOF

    # Create package.json for full-stack app
    cat > package.json << 'EOF'
{
  "name": "openclaw-gateway",
  "version": "1.0.0",
  "description": "OpenClaw Gateway Service with React Frontend",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "dev": "nodemon app.js",
    "build:frontend": "cd frontend && npm run build",
    "install:frontend": "cd frontend && npm install"
  },
  "dependencies": {
    "express": "^4.18.2",
    "path": "^0.12.7"
  },
  "devDependencies": {
    "nodemon": "^2.0.22"
  },
  "keywords": ["openclaw", "gateway", "api", "react", "fullstack"],
  "author": "OpenClaw",
  "license": "MIT",
  "engines": {
    "node": ">=16.0.0"
  }
}
EOF

    # Install backend dependencies
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