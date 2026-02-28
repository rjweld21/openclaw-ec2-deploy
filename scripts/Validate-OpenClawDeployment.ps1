# Complete OpenClaw Deployment Validation - PowerShell version
# Run this from the openclaw-ec2-deploy directory

param(
    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 30,
    
    [Parameter(Mandatory=$false)]
    [string]$TerraformDir = "terraform"
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    
    switch ($Color.ToLower()) {
        "red" { Write-Host $Message -ForegroundColor Red }
        "green" { Write-Host $Message -ForegroundColor Green }
        "yellow" { Write-Host $Message -ForegroundColor Yellow }
        "blue" { Write-Host $Message -ForegroundColor Blue }
        "cyan" { Write-Host $Message -ForegroundColor Cyan }
        "magenta" { Write-Host $Message -ForegroundColor Magenta }
        default { Write-Host $Message }
    }
}

function Test-HttpEndpoint {
    param([string]$Url, [int]$TimeoutSec = 30)
    
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        return @{ Success = $true; StatusCode = $response.StatusCode; Content = $response.Content }
    }
    catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Get-TerraformOutput {
    param([string]$OutputName)
    
    try {
        Set-Location $TerraformDir
        $output = terraform output -raw $OutputName 2>$null
        Set-Location ..
        return $output
    }
    catch {
        Set-Location ..
        return $null
    }
}

# Main validation
Write-ColorOutput "🔍 OpenClaw Deployment Validation" "Blue"
Write-Host "=================================="

# Check Terraform availability
Write-ColorOutput "📊 Checking Terraform..." "Blue"
try {
    $terraformVersion = terraform version
    Write-ColorOutput "✅ Terraform found" "Green"
} catch {
    Write-ColorOutput "❌ Terraform not found. Please install Terraform." "Red"
    exit 1
}

# Check if in correct directory
if (-not (Test-Path $TerraformDir)) {
    Write-ColorOutput "❌ Terraform directory not found. Please run from openclaw-ec2-deploy directory." "Red"
    exit 1
}

# Check if terraform state exists
if (-not (Test-Path "$TerraformDir/terraform.tfstate")) {
    Write-ColorOutput "❌ Terraform state not found. Please run 'terraform apply' first." "Red"
    exit 1
}

Write-ColorOutput "✅ Terraform state found" "Green"

# Get instance information
Write-ColorOutput "📊 Getting instance information..." "Blue"

$instanceIP = Get-TerraformOutput -OutputName "instance_public_ip"
$gatewayUrl = Get-TerraformOutput -OutputName "openclaw_gateway_url"
$healthUrl = Get-TerraformOutput -OutputName "health_check_url"
$sshCommand = Get-TerraformOutput -OutputName "ssh_connection_command"

if (-not $instanceIP) {
    Write-ColorOutput "❌ Could not get instance IP from Terraform output" "Red"
    exit 1
}

Write-ColorOutput "✅ Instance IP: $instanceIP" "Green"
Write-ColorOutput "✅ Gateway URL: $gatewayUrl" "Green"
Write-ColorOutput "✅ Health URL: $healthUrl" "Green"
Write-Host ""

# Test 1: Basic connectivity
Write-ColorOutput "1. Testing basic connectivity..." "Blue"
try {
    $pingResult = Test-Connection -ComputerName $instanceIP -Count 1 -Quiet -TimeoutSec 5 -ErrorAction Stop
    if ($pingResult) {
        Write-ColorOutput "   ✅ Instance is reachable via ping" "Green"
    } else {
        Write-ColorOutput "   ⚠️ Instance ping failed (may be normal if ICMP is blocked)" "Yellow"
    }
} catch {
    Write-ColorOutput "   ⚠️ Ping test failed (may be normal if ICMP is blocked)" "Yellow"
}

# Test 2: SSH connectivity (if key exists)
Write-ColorOutput "`n2. Testing SSH connectivity..." "Blue"
$sshKeyPath = "openclaw-ec2-key.pem"

if (Test-Path $sshKeyPath) {
    Write-ColorOutput "   ✅ SSH key found" "Green"
    # Note: SSH testing on Windows requires additional setup, so we'll skip the actual test
    Write-ColorOutput "   💡 SSH command: $sshCommand" "Cyan"
} else {
    Write-ColorOutput "   ⚠️ SSH key not found at $sshKeyPath" "Yellow"
    Write-ColorOutput "   💡 You may need to save the private key from Terraform output" "Yellow"
    
    # Try to get the private key from terraform output
    try {
        Set-Location $TerraformDir
        $privateKey = terraform output -raw private_key_pem 2>$null
        Set-Location ..
        
        if ($privateKey) {
            Write-ColorOutput "   💡 Private key available in Terraform output. Save it to $sshKeyPath" "Yellow"
        }
    } catch {
        Set-Location ..
    }
}

# Test 3: Health check endpoint
Write-ColorOutput "`n3. Testing health check endpoint (port 8081)..." "Blue"
$healthResult = Test-HttpEndpoint -Url "$healthUrl/health" -TimeoutSec $TimeoutSeconds

if ($healthResult.Success) {
    Write-ColorOutput "   ✅ Health check endpoint responding" "Green"
    
    try {
        $healthData = $healthResult.Content | ConvertFrom-Json
        $status = $healthData.status
        $openclawStatus = $healthData.services.openclawGateway
        
        Write-ColorOutput "   📊 Health status: $status" "Green"
        Write-ColorOutput "   🌐 OpenClaw Gateway service: $openclawStatus" "Green"
        
        if ($openclawStatus -eq "online") {
            Write-ColorOutput "   ✅ OpenClaw Gateway is running properly" "Green"
        } else {
            Write-ColorOutput "   ⚠️ OpenClaw Gateway is not online (may be starting up)" "Yellow"
        }
    } catch {
        Write-ColorOutput "   📄 Response received but couldn't parse JSON" "Green"
    }
} else {
    Write-ColorOutput "   ❌ Health check endpoint not responding" "Red"
    Write-ColorOutput "   💡 Check security groups allow port 8081" "Yellow"
    Write-ColorOutput "   💡 Instance may still be initializing" "Yellow"
}

# Test 4: OpenClaw Gateway endpoint
Write-ColorOutput "`n4. Testing OpenClaw Gateway (port 8080)..." "Blue"
$gatewayEndpoints = @(
    $gatewayUrl,
    "$gatewayUrl/health",
    "$gatewayUrl/status"
)

$gatewayWorking = $false
foreach ($endpoint in $gatewayEndpoints) {
    $result = Test-HttpEndpoint -Url $endpoint -TimeoutSec $TimeoutSeconds
    if ($result.Success) {
        Write-ColorOutput "   ✅ OpenClaw Gateway responding at: $endpoint" "Green"
        $gatewayWorking = $true
        break
    }
}

if (-not $gatewayWorking) {
    Write-ColorOutput "   ❌ OpenClaw Gateway not responding on port 8080" "Red"
    Write-ColorOutput "   💡 Check security groups allow port 8080" "Yellow"
    Write-ColorOutput "   💡 Gateway may still be starting up (try again in a few minutes)" "Yellow"
}

# Test 5: Detailed health analysis
Write-ColorOutput "`n5. Detailed health analysis..." "Blue"
if ($healthResult.Success) {
    try {
        $healthData = $healthResult.Content | ConvertFrom-Json
        
        Write-ColorOutput "   📊 System Information:" "Cyan"
        if ($healthData.system) {
            Write-Host "      - Node.js Version: $($healthData.system.nodeVersion)"
            Write-Host "      - Platform: $($healthData.system.platform)"
            Write-Host "      - Architecture: $($healthData.system.arch)"
        }
        
        Write-ColorOutput "   🕒 Uptime: $([math]::Round($healthData.uptime, 1)) seconds" "Cyan"
        Write-ColorOutput "   🕒 Timestamp: $($healthData.timestamp)" "Cyan"
    } catch {
        Write-ColorOutput "   ⚠️ Could not parse detailed health information" "Yellow"
    }
} else {
    Write-ColorOutput "   ❌ Health endpoint not available for detailed analysis" "Red"
}

# Summary
Write-ColorOutput "`n📋 Validation Summary" "Blue"
Write-Host "====================="

if ($gatewayWorking -and $healthResult.Success) {
    Write-ColorOutput "🎉 SUCCESS: OpenClaw deployment is working!" "Green"
    Write-ColorOutput "   ✅ Health check: PASSED" "Green"
    Write-ColorOutput "   ✅ Gateway access: PASSED" "Green"
    Write-ColorOutput "`n   🌐 Access your OpenClaw instance at: $gatewayUrl" "Green"
    Write-ColorOutput "   📊 Health dashboard at: $healthUrl" "Green"
} elseif ($healthResult.Success -and -not $gatewayWorking) {
    Write-ColorOutput "⚠️ PARTIAL SUCCESS: Health check works, Gateway may be starting" "Yellow"
    Write-ColorOutput "   ✅ Health check: PASSED" "Green"
    Write-ColorOutput "   ⚠️ Gateway access: FAILED" "Yellow"
    Write-ColorOutput "`n   💡 Wait 2-3 minutes and try accessing: $gatewayUrl" "Yellow"
} else {
    Write-ColorOutput "❌ DEPLOYMENT ISSUES DETECTED" "Red"
    Write-ColorOutput "   ❌ Health check: FAILED" "Red"
    Write-ColorOutput "   ❌ Gateway access: FAILED" "Red"
    Write-ColorOutput "`n   💡 Instance may still be initializing (wait 5-10 minutes)" "Yellow"
}

# Next steps
Write-ColorOutput "`n🔄 Next Steps" "Blue"
Write-Host "============="
Write-Host "1. 🌐 Open in browser: $gatewayUrl"
Write-Host "2. 📊 Check health: $healthUrl"
Write-Host "3. 🔍 SSH to instance: $sshCommand"
Write-Host "4. 📝 View logs: ssh -i openclaw-ec2-key.pem ubuntu@$instanceIP 'sudo -u openclaw pm2 logs'"
Write-Host "5. 📊 Check PM2 status: ssh -i openclaw-ec2-key.pem ubuntu@$instanceIP 'sudo -u openclaw pm2 status'"

Write-ColorOutput "`n💡 Troubleshooting" "Blue"
Write-Host "=================="
if (-not $gatewayWorking) {
    Write-Host "🔧 If OpenClaw Gateway is not responding:"
    Write-Host "   - Wait 5-10 minutes for full initialization"
    Write-Host "   - Check AWS Security Groups allow ports 8080, 8081"
    Write-Host "   - SSH to instance and check: sudo -u openclaw pm2 status"
    Write-Host "   - View initialization logs: sudo tail -f /var/log/openclaw-install.log"
    Write-Host "   - Restart services: sudo -u openclaw pm2 restart all"
}

Write-Host "🔧 Common issues:"
Write-Host "   - Security groups: Ensure ports 8080, 8081 are open to 0.0.0.0/0"
Write-Host "   - Instance startup: Initial setup takes 5-10 minutes"
Write-Host "   - SSH access: Save private key from 'terraform output private_key_pem'"
Write-Host "   - Service status: Check PM2 process manager on the instance"

Write-Host ""
Write-ColorOutput "✅ Validation completed" "Green"