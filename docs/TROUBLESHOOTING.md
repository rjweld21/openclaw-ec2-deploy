# Deployment Troubleshooting Guide

## Common GitHub Actions Issues

### 1. AWS Credentials Setup

**Error:** "Unable to locate credentials"
**Fix:** Ensure GitHub secrets are properly set:

```bash
# In GitHub repository settings → Secrets and variables → Actions
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

### 2. Terraform State Backend Issues

**Error:** "Backend configuration changed" or "State lock"
**Fix Options:**

```bash
# Option A: Force unlock (if safe)
terraform force-unlock <LOCK_ID>

# Option B: Import existing resources
terraform import aws_vpc.main vpc-xxxxx
```

### 3. Key Pair Issues

**Error:** "InvalidKeyPair.NotFound"
**Fix:** Either create key pair or leave empty:

```hcl
# In GitHub variables, set:
KEY_PAIR_NAME = ""  # Leave empty for no SSH access
# OR create key pair in AWS EC2 console first
```

### 4. Resource Limits

**Error:** "LimitExceeded" or "InsufficientCapacity"
**Fix:** Check AWS service quotas:

```bash
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
```

### 5. AMI Issues

**Error:** "InvalidAMIID.NotFound"
**Solution:** The user-data script uses data source - should auto-resolve

### 6. Network Issues

**Error:** "InvalidVpcID.NotFound" or subnet issues
**Solution:** VPC creation is in main.tf - should auto-create

## Quick Fixes for Active Runs

### Force Redeploy
```bash
# Add empty commit to retrigger
git commit --allow-empty -m "Retrigger deployment"
git push origin main
```

### Manual Deployment
```bash
cd openclaw-ec2-deploy
terraform init
terraform plan
terraform apply
```

### Emergency Stop
```bash
# Scale down to 0 instances
aws autoscaling set-desired-capacity --auto-scaling-group-name openclaw-dev-asg --desired-capacity 0
```