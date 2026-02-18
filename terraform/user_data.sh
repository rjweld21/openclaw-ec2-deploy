#!/bin/bash

# Update system
apt-get update -y
apt-get upgrade -y

# Install essential packages
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
    lsb-release

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install Node.js (LTS)
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Install PM2 globally
npm install -g pm2

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create openclaw user
useradd -m -s /bin/bash openclaw
usermod -aG sudo openclaw
usermod -aG docker openclaw

# Set up SSH key for ubuntu user
mkdir -p /home/ubuntu/.ssh
echo "${ssh_public_key}" >> /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys

# Set up SSH key for openclaw user
mkdir -p /home/openclaw/.ssh
echo "${ssh_public_key}" >> /home/openclaw/.ssh/authorized_keys
chown -R openclaw:openclaw /home/openclaw/.ssh
chmod 700 /home/openclaw/.ssh
chmod 600 /home/openclaw/.ssh/authorized_keys

# Enable and start services
systemctl enable docker
systemctl start docker

# Create application directory
mkdir -p /opt/openclaw
chown openclaw:openclaw /opt/openclaw

# Create a simple health check endpoint
cat > /opt/openclaw/health-check.js << 'EOF'
const http = require('http');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ 
      status: 'healthy', 
      timestamp: new Date().toISOString(),
      uptime: process.uptime()
    }));
  } else {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
      <html>
        <body>
          <h1>OpenClaw EC2 Instance</h1>
          <p>Instance is running successfully!</p>
          <p>Timestamp: ${new Date().toISOString()}</p>
          <p>Uptime: ${process.uptime()} seconds</p>
        </body>
      </html>
    `);
  }
});

const port = process.env.PORT || 8080;
server.listen(port, () => {
  console.log(`Health check server running on port ${port}`);
});
EOF

chown openclaw:openclaw /opt/openclaw/health-check.js

# Start the health check service with PM2
su - openclaw -c "cd /opt/openclaw && pm2 start health-check.js --name openclaw-health"
su - openclaw -c "pm2 startup"
su - openclaw -c "pm2 save"

# Log completion
echo "EC2 instance initialization completed at $(date)" >> /var/log/user-data.log