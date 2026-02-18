# OpenClaw EC2 Deploy

A comprehensive AWS EC2 deployment infrastructure with automated provisioning, monitoring, and management capabilities.

## 🚀 Features

- **Automated EC2 provisioning** with Terraform
- **Comprehensive AWS credential validation**
- **VPC with proper networking setup**
- **Security groups with controlled access**
- **Automatic SSH key generation and management**
- **Health monitoring endpoint**
- **Docker and Node.js pre-installed**
- **PM2 process management**
- **Detailed deployment status monitoring**

## 📋 Prerequisites

1. **Node.js** (>= 16.0.0)
2. **Terraform** (>= 1.0)
3. **AWS CLI** (optional but recommended)
4. **Valid AWS credentials** with EC2, VPC, and IAM permissions

## 🔧 Setup

1. **Clone or create the project:**
   ```bash
   mkdir openclaw-ec2-deploy
   cd openclaw-ec2-deploy
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Configure AWS credentials:**
   Edit the `.env` file with your AWS credentials:
   ```env
   AWS_ACCESS_KEY_ID=your_access_key_here
   AWS_SECRET_ACCESS_KEY=your_secret_key_here
   AWS_REGION=us-east-1
   ```

## 🎯 Usage

### Validate AWS Credentials
```bash
npm run validate-aws
```
This will test your AWS credentials and verify permissions.

### Deploy Infrastructure
```bash
npm run deploy
```
This will:
- Validate AWS credentials
- Initialize Terraform
- Plan the deployment
- Apply the infrastructure
- Save the private SSH key
- Display connection information

### Check Status
```bash
npm run status
```
This will show:
- Instance status and details
- Health endpoint status
- SSH connection command
- Available management commands

### Destroy Infrastructure
```bash
npm run destroy
```
⚠️ **Warning:** This permanently destroys all AWS resources!

## 🏗️ Architecture

### AWS Resources Created

- **VPC** with DNS support
- **Internet Gateway** for public access
- **Public Subnet** in first availability zone
- **Route Table** with internet routing
- **Security Group** with ports:
  - 22 (SSH)
  - 80 (HTTP)
  - 443 (HTTPS)
  - 8080 (Health check)
- **EC2 Key Pair** (auto-generated)
- **EC2 Instance** (Ubuntu 22.04 LTS)
  - Instance type: `t3.micro` (configurable)
  - 20GB encrypted EBS volume
  - Docker pre-installed
  - Node.js LTS pre-installed
  - PM2 process manager
  - Health check service running on port 8080

### File Structure
```
openclaw-ec2-deploy/
├── package.json              # Project configuration
├── .env                      # AWS credentials and config
├── README.md                 # This file
├── scripts/
│   ├── validate-aws.js       # AWS credential validation
│   ├── deploy.js             # Deployment orchestration
│   ├── status.js             # Status checking
│   └── destroy.js            # Infrastructure destruction
└── terraform/
    ├── main.tf               # Main Terraform configuration
    └── user_data.sh          # EC2 initialization script
```

## 🔐 Security

- **Encrypted EBS volumes** for data at rest
- **Security groups** with minimal required access
- **SSH key authentication** only
- **No hardcoded credentials** in code
- **Environment variable** based configuration

## 🔍 Monitoring

The deployment includes a health check endpoint accessible at:
```
http://<instance-public-ip>:8080/health
```

Returns JSON status:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "uptime": 3600
}
```

## 🛠️ Customization

### Environment Variables

- `AWS_REGION` - AWS region (default: us-east-1)
- `INSTANCE_TYPE` - EC2 instance type (default: t3.micro)
- `KEY_PAIR_NAME` - SSH key pair name (default: openclaw-ec2-key)

### Terraform Variables

You can customize the deployment by modifying variables in `terraform/main.tf` or using environment variables:
- `TF_VAR_aws_region`
- `TF_VAR_instance_type`
- `TF_VAR_key_pair_name`
- `TF_VAR_project_name`

## 📊 Outputs

After successful deployment, you'll get:
- **Instance ID**
- **Public IP address**
- **Public DNS name**
- **SSH connection command**
- **Private key** (saved as `openclaw-ec2-key.pem`)

## 🚨 Troubleshooting

### Common Issues

1. **AWS Credentials Invalid:**
   - Run `npm run validate-aws` to test credentials
   - Ensure your AWS user has EC2, VPC, and IAM permissions

2. **Terraform Not Found:**
   - Install Terraform from https://www.terraform.io/downloads
   - Ensure it's in your system PATH

3. **Instance Not Responding:**
   - Check security group allows inbound traffic on port 8080
   - Wait a few minutes for initialization to complete
   - Check instance status in AWS console

4. **SSH Connection Failed:**
   - Ensure the private key file has correct permissions (600)
   - Use the exact SSH command provided by the status check
   - Verify security group allows SSH (port 22)

### Debugging Commands

```bash
# Check AWS credentials
aws sts get-caller-identity

# Terraform debug
cd terraform && terraform plan

# Check instance logs
# (SSH to instance and check /var/log/user-data.log)
```

## 🔄 Development

To extend this project:

1. **Modify infrastructure:** Edit `terraform/main.tf`
2. **Update initialization:** Edit `terraform/user_data.sh`
3. **Add scripts:** Create new files in `scripts/` directory
4. **Update package.json:** Add new npm scripts as needed

## 📝 License

MIT License - Feel free to use and modify as needed.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📞 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review AWS CloudTrail logs for detailed error information
3. Verify your AWS account limits and permissions
4. Check Terraform state file for resource conflicts

---

**Happy Deploying! 🚀**