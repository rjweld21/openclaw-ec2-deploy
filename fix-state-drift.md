# Fix Terraform State Drift

## Problem
Resources exist in AWS but Terraform state doesn't know about them, causing "already exists" errors.

## Solution: State Refresh & Import

### Step 1: Refresh state to see what Terraform thinks exists
```bash
# This will update state with current reality from AWS
terraform refresh
```

### Step 2: Check what resources Terraform thinks it should manage vs what exists
```bash
# Plan will show what Terraform wants to create/modify/destroy
terraform plan
```

### Step 3: Import existing resources into state (if needed)
If resources exist but aren't in state, import them:
```bash
# Example imports (adjust resource names based on your main.tf):
terraform import aws_vpc.openclaw_vpc vpc-xxxxxxxxx
terraform import aws_internet_gateway.openclaw_igw igw-xxxxxxxxx  
terraform import aws_subnet.public_subnet subnet-xxxxxxxxx
terraform import aws_security_group.openclaw_sg sg-xxxxxxxxx
terraform import aws_instance.openclaw_instance i-xxxxxxxxx
```

### Step 4: Plan again to verify everything is in sync
```bash
terraform plan  # Should show "No changes" if everything is imported correctly
```

## GitHub Actions Approach
Add this workflow job to handle state drift automatically:

```yaml
  fix-state:
    name: Fix State Drift  
    runs-on: ubuntu-latest
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'fix-drift'
    # ... (AWS auth steps) ...
    steps:
      - name: Refresh Terraform State
        run: |
          terraform init
          terraform refresh
          terraform plan -detailed-exitcode
```