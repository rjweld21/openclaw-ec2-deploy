# OpenClaw Connectivity Test - PowerShell version
# Usage: .\Test-OpenClawConnectivity.ps1 -InstanceIP "54.123.45.67"

param(
    [Parameter(Mandatory=$true)]
    [string]$InstanceIP,
    
    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 30
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    
    switch ($Color.ToLower()) {
        "red" { Write-Host $Message -ForegroundColor Red }
        "green" { Write-Host $Message -ForegroundColor Green }
        "yellow" { Write-Host $Message -ForegroundColor Yellow }
        "blue" { Write-Host $Message -ForegroundColor Blue }
        "cyan" { Write-Host $Message -ForegroundColor Cyan }
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

# Main script
Write-ColorOutput "🌐 Testing OpenClaw Connectivity" "Blue"
Write-Host "================================"
Write-Host "Instance IP: $InstanceIP"

$GatewayUrl = "http://${InstanceIP}:8080"
$HealthUrl = "http://${InstanceIP}:8081"

Write-Host "Gateway URL: $GatewayUrl"
Write-Host "Health URL: $HealthUrl"
Write-Host ""

# Test 1: Health check endpoint
Write-ColorOutput "Testing health check endpoint..." "Blue"
$healthResult = Test-HttpEndpoint -Url "$HealthUrl/health" -TimeoutSec $TimeoutSeconds

if ($healthResult.Success) {
    Write-ColorOutput "✅ Health check successful" "Green"
    
    try {
        $healthData = $healthResult.Content | ConvertFrom-Json
        $status = $healthData.status
        $openclawStatus = $healthData.services.openclawGateway
        
        Write-ColorOutput "   📊 Overall status: $status" "Green"
        Write-ColorOutput "   🌐 OpenClaw Gateway: $openclawStatus" "Green"
        
        if ($openclawStatus -eq "online") {
            Write-ColorOutput "   ✅ OpenClaw Gateway is running" "Green"
        } else {
            Write-ColorOutput "   ⚠️ OpenClaw Gateway may be starting up" "Yellow"
        }
    }
    catch {
        Write-ColorOutput "   📄 Response received (JSON parsing failed)" "Green"
    }
} else {
    Write-ColorOutput "❌ Health check failed: $($healthResult.Error)" "Red"
    Write-ColorOutput "💡 Instance may still be starting up (wait 2-3 minutes)" "Yellow"
}

Write-Host ""

# Test 2: OpenClaw Gateway
Write-ColorOutput "Testing OpenClaw Gateway..." "Blue"
$gatewayEndpoints = @(
    $GatewayUrl,
    "$GatewayUrl/health",
    "$GatewayUrl/status"
)

$gatewayResponding = $false
foreach ($endpoint in $gatewayEndpoints) {
    $result = Test-HttpEndpoint -Url $endpoint -TimeoutSec $TimeoutSeconds
    if ($result.Success) {
        Write-ColorOutput "✅ Gateway responding at: $endpoint" "Green"
        $gatewayResponding = $true
        break
    }
}

if (-not $gatewayResponding) {
    Write-ColorOutput "❌ OpenClaw Gateway not responding" "Red"
    Write-ColorOutput "💡 Gateway may still be initializing" "Yellow"
}

Write-Host ""

# Test 3: Basic ping test
Write-ColorOutput "Testing basic connectivity..." "Blue"
try {
    $pingResult = Test-Connection -ComputerName $InstanceIP -Count 1 -Quiet -ErrorAction Stop
    if ($pingResult) {
        Write-ColorOutput "✅ Instance is reachable via ping" "Green"
    } else {
        Write-ColorOutput "⚠️ Instance ping failed (may be normal if ICMP is blocked)" "Yellow"
    }
} catch {
    Write-ColorOutput "⚠️ Ping test failed (may be normal if ICMP is blocked)" "Yellow"
}

Write-Host ""

# Browser access info
Write-ColorOutput "🌐 Browser Access" "Blue"
Write-Host "=================="
Write-Host "Try opening these URLs in your browser:"
Write-ColorOutput "📊 Health Dashboard: $HealthUrl" "Cyan"
Write-ColorOutput "🌐 OpenClaw Gateway: $GatewayUrl" "Cyan"

Write-Host ""

# Final status
if ($gatewayResponding) {
    Write-ColorOutput "🎉 SUCCESS: OpenClaw appears to be running!" "Green"
    Write-ColorOutput "   Access it at: $GatewayUrl" "Green"
} else {
    Write-ColorOutput "⏳ OpenClaw may still be starting up" "Yellow"
    Write-ColorOutput "   Wait a few minutes and try again" "Yellow"
    Write-ColorOutput "   Initial setup can take 3-5 minutes after EC2 launch" "Yellow"
}

Write-Host ""
Write-ColorOutput "💡 Troubleshooting Tips" "Blue"
Write-Host "======================"
Write-Host "- If nothing responds: Check AWS Security Groups allow ports 8080, 8081"
Write-Host "- If slow responses: EC2 instance may still be initializing"
Write-Host "- For SSH access: Use the private key from Terraform output"
Write-Host "- To restart services: SSH to instance and run 'sudo -u openclaw pm2 restart all'"