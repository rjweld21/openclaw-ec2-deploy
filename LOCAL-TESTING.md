# 🧪 Local Testing Guide for OpenClaw

This guide shows you multiple ways to test OpenClaw locally and access remote instances.

## 🎯 Quick Start: Test Remote Access

### Method 1: Test Known IP Addresses
```powershell
# Run the automated tester
.\test-remote-access.ps1

# Or test a specific IP address
.\test-remote-access.ps1 -InstanceIP "100.53.34.220"

# Discover any running instances (requires AWS CLI)
.\test-remote-access.ps1 -DiscoverInstances
```

### Method 2: Manual Browser Testing
Try opening these URLs in your browser:
- **Primary Instance**: http://100.53.34.220:8080 (OpenClaw Gateway)
- **Health Check**: http://100.53.34.220:8081 (Health Dashboard)  
- **Alternative**: http://34.201.3.103:8080 (if first doesn't work)

---

## 🔧 Local OpenClaw Installation & Testing

### Option A: Install OpenClaw Locally
```powershell
# Install Node.js LTS first (if not installed)
# Download from: https://nodejs.org/

# Install OpenClaw globally
npm install -g openclaw

# Verify installation
openclaw --version

# Create local workspace
mkdir C:\openclaw-local
cd C:\openclaw-local

# Create basic config
New-Item -Path "config.json" -ItemType File -Value @"
{
  "server": {
    "port": 8080,
    "host": "127.0.0.1"
  },
  "gateway": {
    "enabled": true,
    "port": 8080
  },
  "anthropic": {
    "api_key": "your-api-key-here"
  },
  "workspace": "./workspace"
}
"@

# Start OpenClaw Gateway
openclaw gateway start --config config.json
```

**Then access**: http://localhost:8080

### Option B: Docker Testing (Alternative)
```powershell
# If you have Docker Desktop installed
docker run -d -p 8080:8080 --name openclaw-test openclaw/openclaw:latest

# Check if it's running
docker ps

# View logs
docker logs openclaw-test

# Access at: http://localhost:8080
```

---

## 🔍 Remote Instance Debugging

### Get Instance Information
```powershell
# If you have AWS CLI configured
aws ec2 describe-instances --filters "Name=tag:Project,Values=openclaw" --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' --output table
```

### SSH to Remote Instance (if key available)
```powershell
# If you have the SSH private key from deployment
ssh -i openclaw-ec2-key.pem ubuntu@100.53.34.220

# Once connected, check OpenClaw status:
sudo -u openclaw pm2 status
sudo -u openclaw pm2 logs

# Check installation logs
sudo tail -f /var/log/openclaw-install.log

# Restart services if needed
sudo -u openclaw pm2 restart all
```

---

## 📊 Validation Scripts

### PowerShell Validation (Recommended)
```powershell
# Use our comprehensive validation script
.\scripts\Validate-OpenClawDeployment.ps1

# Or quick connectivity test
.\scripts\Test-OpenClawConnectivity.ps1 -InstanceIP "100.53.34.220"
```

### Manual Validation
```powershell
# Test connectivity
Test-NetConnection -ComputerName 100.53.34.220 -Port 8080
Test-NetConnection -ComputerName 100.53.34.220 -Port 8081

# Test HTTP endpoints
Invoke-WebRequest -Uri "http://100.53.34.220:8080" -TimeoutSec 10
Invoke-WebRequest -Uri "http://100.53.34.220:8081/health" -TimeoutSec 10
```

---

## 🌐 Browser Access Methods

### Direct Access
If any remote instance is working, you can access it directly:
1. **OpenClaw Gateway**: `http://[instance-ip]:8080`
2. **Health Dashboard**: `http://[instance-ip]:8081`

### Expected Interface
When OpenClaw is working, you should see:
- OpenClaw web interface on port 8080
- Health status JSON on port 8081/health
- Interactive terminal/chat interface
- File management and workspace access

---

## 🔧 Troubleshooting

### Common Issues & Solutions

**1. "Connection Refused" or Timeout:**
- Instance may not be running: Check AWS Console
- Security groups: Ensure ports 8080, 8081 are open
- Services not started: SSH and check `pm2 status`

**2. "Instance Not Found":**
- Infrastructure deployment failed
- Check GitHub Actions logs for deployment status
- May need to retry deployment

**3. "Services Not Responding":**
- OpenClaw installation may have failed
- SSH to instance and check `/var/log/openclaw-install.log`
- Restart services: `sudo -u openclaw pm2 restart all`

**4. "Permission Denied" (SSH):**
- SSH key not available or wrong permissions
- Get key from terraform output: `terraform output private_key_pem`
- Set permissions: `chmod 600 openclaw-ec2-key.pem` (Linux/Mac)

### Debug Commands
```powershell
# Quick health check from PowerShell
$ip = "100.53.34.220"
try {
    $response = Invoke-RestMethod -Uri "http://$ip:8081/health" -TimeoutSec 5
    Write-Host "Status: $($response.status)"
    Write-Host "OpenClaw Gateway: $($response.services.openclawGateway)"
} catch {
    Write-Host "Health check failed: $($_.Exception.Message)"
}
```

---

## 🎯 Success Indicators

**✅ Working OpenClaw Instance:**
- Health endpoint returns: `{"status": "healthy", "services": {"openclawGateway": "online"}}`
- Gateway port 8080 loads OpenClaw web interface
- Can interact with OpenClaw chat/terminal
- File operations work in workspace

**❌ Failed Instance:**
- Ports 8080/8081 don't respond (connection timeout/refused)
- Health endpoint returns error or "degraded" status
- OpenClaw Gateway shows as "offline"
- SSH shows PM2 processes stopped or errored

---

## 📞 Getting Help

**If nothing works:**
1. Run `.\test-remote-access.ps1 -DiscoverInstances`
2. Check GitHub Actions logs for latest deployment
3. Try the validation scripts in the `scripts/` directory
4. SSH to any running instance for direct debugging

**If OpenClaw works locally but not remotely:**
- Compare local vs remote configurations
- Check network/firewall settings
- Verify API key configuration on remote instance

The goal is to get you connected to a working OpenClaw interface where you can interact with the system! 🚀