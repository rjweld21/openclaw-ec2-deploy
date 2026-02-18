# OpenClaw EC2 Deployment

🚀 **Production-ready OpenClaw Gateway deployment on AWS EC2** with automated GitHub Actions CI/CD pipeline for 24/7 cloud operation.

## ✨ Features

- **🏗️ Infrastructure as Code**: Complete Terraform configuration
- **🔄 Automated CI/CD**: GitHub Actions with validation and deployment
- **🛡️ Security-First**: Restrictive security groups, SSL/TLS, fail2ban
- **📊 Monitoring**: CloudWatch integration, health checks, alerting
- **🔧 Auto-Recovery**: PM2 process management, auto-scaling groups
- **💰 Cost-Optimized**: Right-sized instances with intelligent scaling
- **🔒 Zero-Trust Network**: VPC isolation, minimal permissions

## 🏛️ Architecture

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   Application       │    │     Auto Scaling    │    │      CloudWatch     │
│   Load Balancer     │───▶│        Group        │───▶│     Monitoring      │
│   (SSL Termination) │    │   (High Availability)│    │   (Logs & Metrics)  │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
           │                           │                           │
           ▼                           ▼                           ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│      Security       │    │    EC2 Instances    │    │        IAM          │
│      Groups         │    │  (OpenClaw Gateway)  │    │   (Minimal Perms)   │
│  (Network Security) │    │   PM2 + Nginx       │    │                     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

## 📋 Prerequisites

- **AWS Account** with appropriate permissions
- **GitHub Account** with repository access
- **AWS Key Pair** for SSH access (create in EC2 console)
- **Domain Name** (optional, for SSL/custom domain)

## 🚀 Quick Start

### 1. Repository Setup

```bash
# Clone or fork this repository
git clone https://github.com/your-username/openclaw-ec2-deploy.git
cd openclaw-ec2-deploy

# Make scripts executable
chmod +x scripts/*.sh
```

### 2. Configure GitHub Secrets

Run the interactive setup script:

```bash
./scripts/setup-secrets.sh
```

Or set manually in GitHub repository settings → Secrets and variables → Actions:

| Secret Name | Description | Required |
|-------------|-------------|----------|
| `AWS_ACCESS_KEY_ID` | AWS Access Key | ✅ |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Key | ✅ |
| `AWS_KEY_PAIR_NAME` | EC2 Key Pair name | ✅ |
| `ALLOWED_SSH_CIDR` | SSH access CIDR (e.g., your IP) | ✅ |
| `DOMAIN_NAME` | Custom domain for SSL | ❌ |

### 3. Deploy to AWS

```bash
# Commit and push to trigger deployment
git add .
git commit -m "Deploy OpenClaw Gateway to AWS EC2"
git push origin main
```

GitHub Actions will automatically:
- ✅ Validate Terraform configuration
- 🏗️ Provision AWS infrastructure  
- 🚀 Deploy OpenClaw Gateway
- 🔍 Run health checks
- 📊 Create deployment status

### 4. Access Your Gateway

After deployment completes:
- **Load Balancer URL**: Check GitHub Actions output or AWS Console
- **Health Check**: `http://your-lb-dns/health`
- **OpenClaw Gateway**: `http://your-lb-dns/` (requires auth token)

## 📁 Project Structure

```
openclaw-ec2-deploy/
├── 📁 .github/workflows/          # GitHub Actions CI/CD
│   └── deploy.yml                # Main deployment workflow
├── 📁 infrastructure/            # Terraform Infrastructure
│   ├── main.tf                  # Core AWS resources
│   ├── user-data.sh             # EC2 bootstrap script  
│   └── terraform.tfvars.example # Configuration template
├── 📁 scripts/                   # Utilities & Tools
│   ├── setup-secrets.sh         # GitHub secrets setup
│   ├── monitor-deployment.sh    # Health monitoring
│   └── maintenance/             # Maintenance scripts
└── 📄 README.md                 # This file
```

## ⚙️ Configuration

### Infrastructure Settings

Copy `infrastructure/terraform.tfvars.example` to `terraform.tfvars`:

```hcl
# AWS Configuration
aws_region = "us-east-1"

# EC2 Configuration  
instance_type = "t3.small"          # t3.micro, t3.small, t3.medium
key_pair_name = "my-aws-keypair"    # Your AWS Key Pair

# Security Configuration
allowed_ssh_cidrs = ["203.0.113.0/32"]  # Your IP for SSH access

# Optional: SSL Configuration
domain_name = "openclaw.yourdomain.com"  # For custom SSL
```

### Instance Types & Sizing

| Type | vCPU | Memory | Network | Use Case |
|------|------|--------|---------|----------|
| `t3.micro` | 2 | 1 GB | Low-Moderate | Development/Testing |
| `t3.small` | 2 | 2 GB | Low-Moderate | **Recommended** |
| `t3.medium` | 2 | 4 GB | Low-Moderate | Heavy Usage |
| `t3.large` | 2 | 8 GB | Moderate | Enterprise |

## 🔧 Management & Operations

### Monitoring Deployment Health

```bash
# One-time health check
./scripts/monitor-deployment.sh

# Continuous monitoring  
./scripts/monitor-deployment.sh --continuous

# Include SSL checks
./scripts/monitor-deployment.sh --domain openclaw.yourdomain.com
```

### Manual Deployment

```bash
cd infrastructure

# Initialize Terraform
terraform init

# Plan deployment
terraform plan \
  -var="key_pair_name=my-keypair" \
  -var="allowed_ssh_cidrs=[\"$(curl -s https://api.ipify.org)/32\"]"

# Deploy infrastructure
terraform apply -auto-approve
```

### Scaling Operations

```bash
# Scale up instances
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name openclaw-asg \
  --desired-capacity 2

# Scale down
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name openclaw-asg \
  --desired-capacity 1
```

### SSH Access

```bash
# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=openclaw-gateway" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# Connect via SSH
ssh -i ~/.ssh/your-keypair.pem ubuntu@$INSTANCE_IP
```

### Log Analysis

```bash
# View OpenClaw logs
sudo tail -f /var/log/openclaw/gateway.log

# View PM2 logs  
sudo -u openclaw pm2 logs openclaw-gateway

# View Nginx logs
sudo tail -f /var/log/nginx/access.log
```

## 🔒 Security Features

- **🛡️ VPC Isolation**: Dedicated virtual private cloud
- **🚪 Security Groups**: Restrictive network access controls
- **🔐 SSL/TLS**: Automated certificate management
- **🚫 Fail2Ban**: Intrusion prevention system
- **🔥 UFW Firewall**: Host-based firewall rules
- **🔑 IAM Roles**: Minimal required permissions
- **📝 Audit Logging**: CloudWatch integration

### Security Best Practices

1. **Restrict SSH Access**: Use specific CIDR blocks, not `0.0.0.0/0`
2. **Rotate Keys**: Regularly rotate AWS access keys and OpenClaw tokens
3. **Monitor Logs**: Set up CloudWatch alarms for suspicious activity
4. **Update Regularly**: Enable automatic security updates
5. **Backup Data**: Regular automated backups to S3

## 🏥 Health Checks & Monitoring

### Built-in Health Checks

- **Load Balancer**: HTTP health checks every 30 seconds
- **Auto Scaling**: ELB health check integration
- **PM2**: Process-level health monitoring
- **Custom Script**: Application-specific health validation

### CloudWatch Metrics

- **System Metrics**: CPU, Memory, Disk, Network
- **Application Metrics**: OpenClaw Gateway health
- **Log Aggregation**: Centralized log collection
- **Custom Alarms**: Configurable alerting thresholds

## 🔄 CI/CD Pipeline

### Workflow Triggers

- **Push to `main`**: Automatic deployment
- **Pull Request**: Validation and security scanning  
- **Manual Dispatch**: On-demand deployment/destruction
- **Schedule**: Optional scheduled deployments

### Pipeline Stages

1. **🔍 Validation**: Terraform format, validate, plan
2. **🛡️ Security Scan**: Infrastructure security analysis
3. **🏗️ Deployment**: Infrastructure provisioning
4. **🔍 Health Checks**: Post-deployment validation
5. **📊 Reporting**: Deployment status and metrics

## 🆘 Troubleshooting

### Common Issues

#### Deployment Fails with "Invalid Key Pair"
- Verify key pair exists in the target AWS region
- Check `AWS_KEY_PAIR_NAME` secret is set correctly

#### Health Checks Failing
```bash
# Check instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=openclaw-gateway"

# Check application logs
ssh -i ~/.ssh/your-key.pem ubuntu@INSTANCE_IP
sudo tail -f /var/log/openclaw-bootstrap.log
```

#### SSL Certificate Issues
- Verify domain DNS points to load balancer
- Check certificate validation in AWS Certificate Manager
- Ensure domain is accessible from internet

#### High CPU/Memory Usage
```bash
# Check resource usage
ssh -i ~/.ssh/your-key.pem ubuntu@INSTANCE_IP
htop

# Check OpenClaw processes
sudo -u openclaw pm2 status
```

### Recovery Procedures

#### Emergency Stop
```bash
# Scale down to 0 instances
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name openclaw-asg \
  --desired-capacity 0
```

#### Full Disaster Recovery
```bash
# Restore from backup (if configured)
./scripts/restore-backup.sh

# Or destroy and redeploy
terraform destroy -auto-approve
git push origin main  # Triggers redeployment
```

## 💰 Cost Optimization

### Estimated Monthly Costs (us-east-1)

| Component | Type | Monthly Cost |
|-----------|------|-------------|
| EC2 Instance | t3.small | ~$15.00 |
| Load Balancer | Application | ~$18.00 |
| CloudWatch | Logs + Metrics | ~$5.00 |
| Data Transfer | 1GB/month | ~$1.00 |
| **Total** | | **~$39.00** |

### Cost-Saving Tips

1. **Use Spot Instances**: Save up to 70% (requires configuration)
2. **Reserved Instances**: Save 30-60% with 1-year commitment
3. **Right-size Instances**: Monitor usage, scale down if possible
4. **Schedule Downtime**: Use automation to stop non-prod instances
5. **Optimize Data Transfer**: Use CloudFront for static assets

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes and test thoroughly
4. Commit changes: `git commit -m 'Add amazing feature'`
5. Push to branch: `git push origin feature/amazing-feature`  
6. Create a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **📖 Documentation**: [OpenClaw Docs](https://docs.openclaw.ai)
- **💬 Community**: [Discord Server](https://discord.com/invite/clawd)
- **🐛 Issues**: [GitHub Issues](https://github.com/your-username/openclaw-ec2-deploy/issues)
- **📧 Email**: support@openclaw.ai

## 🔗 Related Projects

- **[OpenClaw](https://github.com/openclaw/openclaw)**: Main OpenClaw repository
- **[ClawHub](https://clawhub.com)**: Skill and integration marketplace
- **[OpenClaw Docker](https://github.com/openclaw/openclaw-docker)**: Docker deployment
- **[OpenClaw Kubernetes](https://github.com/openclaw/openclaw-k8s)**: Kubernetes deployment

---

**Made with ❤️ for the OpenClaw community**