# Test Remote OpenClaw Access - PowerShell Script
# This script helps you discover and test any existing OpenClaw instances

param(
    [Parameter(Mandatory=$false)]
    [string]$InstanceIP,
    
    [Parameter(Mandatory=$false)]
    [switch]$DiscoverInstances
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

function Test-OpenClawEndpoint {
    param([string]$Url)
    
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        return @{ Success = $true; StatusCode = $response.StatusCode; Content = $response.Content }
    }
    catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

Write-ColorOutput "🌐 OpenClaw Remote Access Tester" "Blue"
Write-Host "=================================="

if ($DiscoverInstances) {
    Write-ColorOutput "🔍 Discovering EC2 instances..." "Blue"
    
    # Check if AWS CLI is available
    try {
        $awsInstances = aws ec2 describe-instances --filters "Name=tag:Project,Values=openclaw" --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' --output table 2>$null
        
        if ($awsInstances) {
            Write-ColorOutput "📊 OpenClaw EC2 Instances Found:" "Green"
            Write-Host $awsInstances
        } else {
            Write-ColorOutput "❌ No OpenClaw instances found or AWS CLI not configured" "Yellow"
        }
    }
    catch {
        Write-ColorOutput "⚠️ AWS CLI not available or not configured" "Yellow"
        Write-ColorOutput "💡 Install AWS CLI and configure credentials to discover instances" "Cyan"
    }
}

# Test known IP addresses from our deployment attempts
$knownIPs = @(
    "100.53.34.220",  # From previous deployment logs
    "34.201.3.103"    # From earlier attempts
)

Write-ColorOutput "`n🧪 Testing Known IP Addresses..." "Blue"

foreach ($ip in $knownIPs) {
    Write-ColorOutput "Testing $ip..." "Cyan"
    
    # Test OpenClaw Gateway (port 8080)
    $gatewayResult = Test-OpenClawEndpoint -Url "http://$ip:8080"
    if ($gatewayResult.Success) {
        Write-ColorOutput "   ✅ OpenClaw Gateway responding at http://$ip:8080" "Green"
        Write-ColorOutput "   📊 Status Code: $($gatewayResult.StatusCode)" "Green"
    } else {
        Write-ColorOutput "   ❌ Gateway not responding: $($gatewayResult.Error)" "Red"
    }
    
    # Test Health Check (port 8081)  
    $healthResult = Test-OpenClawEndpoint -Url "http://$ip:8081/health"
    if ($healthResult.Success) {
        Write-ColorOutput "   ✅ Health Check responding at http://$ip:8081/health" "Green"
        
        try {
            $healthData = $healthResult.Content | ConvertFrom-Json
            Write-ColorOutput "   📊 Health Status: $($healthData.status)" "Green"
            Write-ColorOutput "   🌐 OpenClaw Gateway Service: $($healthData.services.openclawGateway)" "Green"
        }
        catch {
            Write-ColorOutput "   📄 Health endpoint responding (JSON parse failed)" "Green"
        }
    } else {
        Write-ColorOutput "   ❌ Health check not responding: $($healthResult.Error)" "Red"
    }
    
    Write-Host ""
}

# Test custom IP if provided
if ($InstanceIP) {
    Write-ColorOutput "🎯 Testing Custom IP: $InstanceIP" "Blue"
    
    $gatewayUrl = "http://$InstanceIP:8080"
    $healthUrl = "http://$InstanceIP:8081/health"
    
    Write-ColorOutput "Testing OpenClaw Gateway..." "Cyan"
    $result = Test-OpenClawEndpoint -Url $gatewayUrl
    if ($result.Success) {
        Write-ColorOutput "✅ SUCCESS: OpenClaw Gateway is responding!" "Green"
        Write-ColorOutput "🌐 Access it at: $gatewayUrl" "Green"
    } else {
        Write-ColorOutput "❌ Gateway not responding: $($result.Error)" "Red"
    }
    
    Write-ColorOutput "Testing Health Check..." "Cyan"  
    $healthResult = Test-OpenClawEndpoint -Url $healthUrl
    if ($healthResult.Success) {
        Write-ColorOutput "✅ Health Check responding at: $healthUrl" "Green"
    } else {
        Write-ColorOutput "❌ Health check not responding: $($healthResult.Error)" "Red"
    }
}

Write-ColorOutput "`n💡 Usage Examples:" "Blue"
Write-Host "=================="
Write-Host "Test specific IP:     .\test-remote-access.ps1 -InstanceIP '1.2.3.4'"
Write-Host "Discover instances:   .\test-remote-access.ps1 -DiscoverInstances"
Write-Host "Browse to any working URL shown above to access OpenClaw!"

Write-ColorOutput "`n🔧 Troubleshooting:" "Blue"
Write-Host "=================="
Write-Host "- If no instances respond: Infrastructure may not be deployed yet"
Write-Host "- If ports are blocked: Check AWS Security Groups allow 8080, 8081"
Write-Host "- If services aren't running: OpenClaw installation may have failed"
Write-Host "- For SSH debugging: Use the key from GitHub Actions or terraform output"