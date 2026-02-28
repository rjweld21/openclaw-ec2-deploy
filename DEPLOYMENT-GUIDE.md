# 🚀 Complete OpenClaw EC2 Deployment Guide

This guide covers the complete process from infrastructure deployment to OpenClaw installation and validation.

## 📋 Overview

The deployment process includes:
1. **Infrastructure Setup** - AWS EC2, VPC, Security Groups via Terraform
2. **Automatic OpenClaw Installation** - Complete OpenClaw setup on EC2 startup
3. **Service Configuration** - PM2 process management, systemd backup
4. **Comprehensive Validation** - Multiple verification methods

## 🎯 What Gets Installed

### Infrastructure (Terraform)
- ✅ VPC with proper networking (10.0.0.0/16)
- ✅ Public subnet with internet gateway
- ✅ Security groups (SSH:22, HTTP:80, HTTPS:443, OpenClaw:8080, Health:8081)
- ✅ EC2 instance (Ubuntu 22.04 LTS, default t3.micro)
- ✅ Encrypted 20GB EBS volume
- ✅ Auto-generated SSH key pair

### Software Stack (Automated Installation)
- ✅ **Docker** - Container runtime
- ✅ **Node.js LTS** - JavaScript runtime
- ✅ **PM2** - Process manager
- ✅ **AWS CLI** - Cloud management
- ✅ **OpenClaw** - Installed globally via npm
- ✅ **Health Check Service** - Monitoring endpoint (port 8081)
- ✅ **Systemd Service** - Backup service management

### OpenClaw Configuration
- ✅ **Gateway Service** - Running on port 8080
- ✅ **Workspace Directory** - `/opt/openclaw/data`
- ✅ **Logging** - Comprehensive logs in `/opt/openclaw/logs`
- ✅ **Auto-restart** - PM2 ensures services stay running
- ✅ **Boot Persistence** - Services start automatically on reboot

## 🔧 Step-by-Step Deployment

### Phase 1: Fix State Drift (If Needed)

If you've had previous failed deployments:

1. **Go to GitHub Actions**:
   - Visit: https://github.com/rjweld21/openclaw-ec2-deploy/actions
   - Click "Deploy OpenClaw to EC2"
   - Click "Run workflow"
   - Set: Environment = `dev`, Action = `fix-drift`
   - Click "Run workflow"

2. **Check Results**:
   - ✅ **Success**: Proceed to Phase 2 with action: `apply`
   - ❌ **Failed**: Proceed to Phase 2A with action: `destroy`

### Phase 2A: Clean Deployment (If Fix-Drift Failed)

1. **Destroy Existing Resources**:
   - Run workflow with Action: `destroy`
   - Wait for completion (5-10 minutes)

2. **Deploy Fresh Infrastructure**:
   - Run workflow with Action: `apply`
   - Proceed to Phase 3

### Phase 2B: Standard Deployment

1. **Deploy Infrastructure**:
   - Run workflow with Action: `apply`
   - Monitor deployment progress
   - Wait for completion (10-15 minutes)

### Phase 3: Validation & Access

#### 3.1 Automated Validation

**PowerShell (Windows) - Recommended:**
```powershell
cd openclaw-ec2-deploy
.\scripts\Validate-OpenClawDeployment.ps1
```

**Bash (Linux/Mac):**
```bash
cd openclaw-ec2-deploy
chmod +x scripts/validate-openclaw-remote.sh
./scripts/validate-openclaw-remote.sh
```

#### 3.2 Quick Connectivity Test

If you just have an IP address:

**PowerShell:**
```powershell
.\scripts\Test-OpenClawConnectivity.ps1 -InstanceIP "54.123.45.67"
```

**Bash:**
```bash
./scripts/test-openclaw-connectivity.sh 54.123.45.67
```

#### 3.3 Manual Browser Testing

Get URLs from GitHub Actions workflow output or terraform:

```bash
cd terraform
terraform output openclaw_gateway_url
terraform output health_check_url
```

Then open in browser:
- **OpenClaw Gateway**: `http://your-ip:8080`
- **Health Dashboard**: `http://your-ip:8081`

#### 3.4 SSH Access & Remote Validation

**Get SSH Command:**
```bash
terraform output ssh_connection_command
```

**SSH to Instance:**
```bash
ssh -i openclaw-ec2-key.pem ubuntu@your-instance-ip
```

**Check Services on Instance:**
```bash
# Switch to openclaw user
sudo -u openclaw -i

# Check PM2 status
pm2 status

# View logs
pm2 logs

# Run validation script
/opt/openclaw/validate-installation.sh

# View installation logs
sudo tail -f /var/log/openclaw-install.log
```

## 🔍 Validation Checklist

### ✅ Infrastructure Validation
- [ ] GitHub Actions workflow completed successfully
- [ ] EC2 instance is running in AWS Console
- [ ] Security groups allow ports 22, 80, 443, 8080, 8081
- [ ] Instance has public IP address

### ✅ OpenClaw Installation Validation  
- [ ] Health check endpoint responds: `http://ip:8081/health`
- [ ] Health check shows OpenClaw Gateway as "online"
- [ ] OpenClaw Gateway responds: `http://ip:8080`
- [ ] PM2 shows openclaw-gateway process as "online"

### ✅ Access Validation
- [ ] Can SSH to instance with generated key
- [ ] Can access OpenClaw Gateway in browser
- [ ] Health dashboard loads properly
- [ ] Services restart automatically after reboot

## 🚨 Troubleshooting

### Common Issues & Solutions

#### 1. Gateway Not Responding (Port 8080)
**Symptoms**: Health check works, but Gateway doesn't respond

**Solutions**:
```bash
# SSH to instance and check status
sudo -u openclaw pm2 status

# View logs
sudo -u openclaw pm2 logs openclaw-gateway

# Restart services
sudo -u openclaw pm2 restart all

# Check if OpenClaw is properly installed
which openclaw
openclaw --version
```

#### 2. Health Check Failing (Port 8081)
**Symptoms**: Can't reach health check endpoint

**Solutions**:
1. **Check Security Groups**: Ensure port 8081 is open in AWS Console
2. **Check Service**: SSH and run `sudo -u openclaw pm2 status`
3. **Wait for Initialization**: Initial setup takes 5-10 minutes

#### 3. SSH Connection Failed
**Symptoms**: Can't SSH to instance

**Solutions**:
1. **Save Private Key**:
   ```bash
   cd terraform
   terraform output private_key_pem > ../openclaw-ec2-key.pem
   chmod 600 ../openclaw-ec2-key.pem  # Linux/Mac
   ```

2. **Check Security Group**: Ensure SSH (port 22) is allowed
3. **Verify IP**: Get current IP with `terraform output instance_public_ip`

#### 4. Services Not Starting
**Symptoms**: PM2 shows services as stopped/errored

**Solutions**:
```bash
# SSH to instance
sudo -u openclaw -i

# Check what went wrong
pm2 logs --err

# Restart everything
pm2 delete all
pm2 start /opt/openclaw/ecosystem.config.js

# Check installation logs
sudo tail -f /var/log/openclaw-install.log

# Manual restart of OpenClaw
cd /opt/openclaw
openclaw gateway start
```

#### 5. Installation Still Running
**Symptoms**: Services not ready, installation in progress

**Check Progress**:
```bash
# SSH to instance and check installation logs
sudo tail -f /var/log/openclaw-install.log

# Check if user_data script is still running
sudo ps aux | grep user-data

# Wait for completion message
sudo grep "OpenClaw installation completed" /var/log/openclaw-install.log
```

### Recovery Commands

**Complete Service Reset**:
```bash
sudo -u openclaw pm2 delete all
sudo -u openclaw pm2 start /opt/openclaw/ecosystem.config.js
sudo -u openclaw pm2 save
```

**Manual OpenClaw Reinstall**:
```bash
sudo -u openclaw npm uninstall -g openclaw
sudo -u openclaw npm install -g openclaw
# Then restart services
```

**Systemd Backup Service** (if PM2 fails):
```bash
sudo systemctl start openclaw.service
sudo systemctl status openclaw.service
```

## 📊 Expected Endpoints

After successful deployment, you should have:

| Service | URL | Purpose |
|---------|-----|---------|
| OpenClaw Gateway | `http://ip:8080` | Main OpenClaw interface |
| Health Check | `http://ip:8081` | System health monitoring |
| Health JSON | `http://ip:8081/health` | Health data (JSON) |
| Status JSON | `http://ip:8081/status` | PM2 process status |

## 🔄 Ongoing Management

### Starting/Stopping Services
```bash
sudo -u openclaw pm2 start all      # Start all services
sudo -u openclaw pm2 stop all       # Stop all services  
sudo -u openclaw pm2 restart all    # Restart all services
sudo -u openclaw pm2 reload all     # Zero-downtime reload
```

### Monitoring
```bash
sudo -u openclaw pm2 monit          # Real-time monitoring
sudo -u openclaw pm2 logs           # Live logs
sudo -u openclaw pm2 list           # Process list
```

### Updates
```bash
# Update OpenClaw
sudo -u openclaw npm update -g openclaw

# Restart after update
sudo -u openclaw pm2 restart openclaw-gateway
```

## 🎉 Success Criteria

Your deployment is successful when:

1. ✅ **GitHub Actions workflow** shows green checkmark
2. ✅ **Health check returns**: `{"status": "healthy", "services": {"openclawGateway": "online"}}`
3. ✅ **Gateway responds** at `http://ip:8080`
4. ✅ **PM2 shows** both processes as "online"
5. ✅ **SSH access works** with the generated key
6. ✅ **Services persist** after EC2 reboot

---

## 📞 Support

If you encounter issues:

1. **Run validation scripts** first to identify specific problems
2. **Check logs** on the instance: `/var/log/openclaw-install.log`
3. **Verify PM2 status**: `sudo -u openclaw pm2 status`
4. **Check security groups** in AWS Console
5. **Review GitHub Actions logs** for deployment issues

The deployment includes comprehensive logging and monitoring to help diagnose any issues that arise.