# Complete OpenClaw Deployment Validation
# Checks BOTH CI/CD build status AND infrastructure/service status

param(
    [Parameter(Mandatory=$false)]
    [int]$MaxBuildsToCheck = 5
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
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        return @{ Success = $true; StatusCode = $response.StatusCode; Content = $response.Content }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

Write-ColorOutput "🔍 Complete OpenClaw Deployment Validation" "Blue"
Write-Host "=============================================="
Write-Host ""

## STEP 1: CI/CD BUILD STATUS VALIDATION
Write-ColorOutput "📊 STEP 1: CI/CD Build Status Validation" "Blue"
Write-Host "----------------------------------------"

$buildStatusOk = $false
$latestSuccessfulBuild = $null

try {
    Write-ColorOutput "Checking recent GitHub Actions builds..." "Cyan"
    
    # Get recent workflow runs
    $runs = gh run list --workflow="deploy.yml" --limit $MaxBuildsToCheck --json status,conclusion,displayTitle,createdAt,htmlUrl
    
    if ($runs) {
        $runsData = $runs | ConvertFrom-Json
        
        Write-ColorOutput "📋 Recent Build History:" "Yellow"
        foreach ($run in $runsData) {
            $status = if ($run.conclusion -eq "success") { "✅" } 
                     elseif ($run.conclusion -eq "failure") { "❌" }
                     elseif ($run.status -eq "in_progress") { "🔄" }
                     else { "⚠️" }
            
            $color = if ($run.conclusion -eq "success") { "Green" }
                    elseif ($run.conclusion -eq "failure") { "Red" }
                    else { "Yellow" }
            
            $time = ([DateTime]$run.createdAt).ToString("MM/dd HH:mm")
            Write-ColorOutput "   $status $($run.displayTitle) ($time)" $color
            
            # Check for latest successful build
            if ($run.conclusion -eq "success" -and -not $latestSuccessfulBuild) {
                $latestSuccessfulBuild = $run
                $buildStatusOk = $true
            }
        }
        
        Write-Host ""
        
        if ($latestSuccessfulBuild) {
            Write-ColorOutput "✅ LATEST SUCCESSFUL BUILD FOUND:" "Green"
            Write-ColorOutput "   Title: $($latestSuccessfulBuild.displayTitle)" "Green"  
            Write-ColorOutput "   Time: $([DateTime]$latestSuccessfulBuild.createdAt)" "Green"
            Write-ColorOutput "   URL: $($latestSuccessfulBuild.htmlUrl)" "Cyan"
        } else {
            Write-ColorOutput "❌ NO RECENT SUCCESSFUL BUILDS FOUND" "Red"
            Write-ColorOutput "   All recent builds have failed!" "Red"
            Write-ColorOutput "   📊 Latest $MaxBuildsToCheck builds all show failures" "Yellow"
        }
        
    } else {
        Write-ColorOutput "⚠️ Could not retrieve build status (gh CLI not available/configured)" "Yellow"
    }
    
} catch {
    Write-ColorOutput "⚠️ Failed to check CI/CD status: $($_.Exception.Message)" "Yellow"
}

Write-Host ""

## STEP 2: INFRASTRUCTURE STATUS VALIDATION  
Write-ColorOutput "🏗️ STEP 2: Infrastructure Status Validation" "Blue"
Write-Host "-------------------------------------------"

$infrastructureOk = $false
$runningInstances = @()

try {
    Write-ColorOutput "Checking AWS EC2 instances..." "Cyan"
    
    # Check for OpenClaw instances
    $awsResult = aws ec2 describe-instances --filters "Name=tag:Project,Values=openclaw" --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' --output json 2>$null
    
    if ($awsResult) {
        $instances = $awsResult | ConvertFrom-Json
        
        if ($instances -and $instances.Count -gt 0) {
            Write-ColorOutput "📊 Found OpenClaw EC2 Instances:" "Yellow"
            
            foreach ($reservation in $instances) {
                foreach ($instance in $reservation) {
                    $instanceId = $instance[0]
                    $state = $instance[1]  
                    $publicIp = $instance[2]
                    $name = $instance[3]
                    
                    $statusIcon = if ($state -eq "running") { "🟢" } 
                                 elseif ($state -eq "stopped") { "🔴" }
                                 elseif ($state -eq "pending") { "🟡" }
                                 else { "⚪" }
                    
                    $color = if ($state -eq "running") { "Green" } else { "Red" }
                    
                    Write-ColorOutput "   $statusIcon $instanceId ($name) - $state" $color
                    if ($publicIp -and $publicIp -ne "null") {
                        Write-ColorOutput "      Public IP: $publicIp" "Cyan"
                        if ($state -eq "running") {
                            $runningInstances += $publicIp
                            $infrastructureOk = $true
                        }
                    } else {
                        Write-ColorOutput "      Public IP: None (private subnet)" "Yellow"
                    }
                }
            }
        } else {
            Write-ColorOutput "❌ No OpenClaw instances found" "Red"
        }
    } else {
        Write-ColorOutput "⚠️ Could not check AWS instances (AWS CLI not configured)" "Yellow"
    }
    
} catch {
    Write-ColorOutput "⚠️ Failed to check infrastructure: $($_.Exception.Message)" "Yellow"
}

Write-Host ""

## STEP 3: SERVICE STATUS VALIDATION
Write-ColorOutput "🌐 STEP 3: Service Status Validation" "Blue" 
Write-Host "------------------------------------"

$servicesOk = $false
$workingEndpoints = @()

if ($runningInstances.Count -gt 0) {
    Write-ColorOutput "Testing OpenClaw services on running instances..." "Cyan"
    
    foreach ($ip in $runningInstances) {
        Write-ColorOutput "Testing $ip..." "Yellow"
        
        # Test OpenClaw Gateway (port 8080)
        $gatewayResult = Test-HttpEndpoint -Url "http://$ip:8080"
        if ($gatewayResult.Success) {
            Write-ColorOutput "   ✅ OpenClaw Gateway responding (port 8080)" "Green"
            $workingEndpoints += "http://$ip:8080"
            $servicesOk = $true
        } else {
            Write-ColorOutput "   ❌ Gateway not responding: $($gatewayResult.Error)" "Red"
        }
        
        # Test Health Check (port 8081)
        $healthResult = Test-HttpEndpoint -Url "http://$ip:8081/health"
        if ($healthResult.Success) {
            Write-ColorOutput "   ✅ Health Check responding (port 8081)" "Green"
            
            try {
                $healthData = $healthResult.Content | ConvertFrom-Json
                $overallStatus = $healthData.status
                $gatewayStatus = $healthData.services.openclawGateway
                
                Write-ColorOutput "      📊 Health Status: $overallStatus" "Green"
                Write-ColorOutput "      🌐 Gateway Service: $gatewayStatus" "Green"
                
                if ($gatewayStatus -eq "online") {
                    $servicesOk = $true
                }
                
            } catch {
                Write-ColorOutput "      📄 Health endpoint responding (JSON parse failed)" "Yellow"
            }
        } else {
            Write-ColorOutput "   ❌ Health Check not responding: $($healthResult.Error)" "Red"
        }
        
        Write-Host ""
    }
} else {
    Write-ColorOutput "⚠️ No running instances with public IPs to test" "Yellow"
}

## STEP 4: OVERALL VALIDATION SUMMARY
Write-Host ""
Write-ColorOutput "🎯 OVERALL DEPLOYMENT STATUS" "Blue"
Write-Host "============================="

$overallSuccess = $buildStatusOk -and $infrastructureOk -and $servicesOk

if ($overallSuccess) {
    Write-ColorOutput "🎉 ✅ DEPLOYMENT VALIDATION: SUCCESS" "Green"
    Write-ColorOutput "   ✅ Latest CI/CD build: PASSED" "Green"
    Write-ColorOutput "   ✅ Infrastructure: RUNNING" "Green" 
    Write-ColorOutput "   ✅ OpenClaw Services: RESPONDING" "Green"
    Write-Host ""
    Write-ColorOutput "🌐 Working OpenClaw Endpoints:" "Green"
    foreach ($endpoint in $workingEndpoints) {
        Write-ColorOutput "   $endpoint" "Cyan"
    }
} else {
    Write-ColorOutput "❌ DEPLOYMENT VALIDATION: FAILED" "Red"
    Write-ColorOutput "   CI/CD Status: $(if ($buildStatusOk) { '✅ PASSED' } else { '❌ FAILED' })" $(if ($buildStatusOk) { "Green" } else { "Red" })
    Write-ColorOutput "   Infrastructure: $(if ($infrastructureOk) { '✅ RUNNING' } else { '❌ NOT RUNNING' })" $(if ($infrastructureOk) { "Green" } else { "Red" })
    Write-ColorOutput "   Services: $(if ($servicesOk) { '✅ RESPONDING' } else { '❌ NOT RESPONDING' })" $(if ($servicesOk) { "Green" } else { "Red" })
    
    Write-Host ""
    Write-ColorOutput "🔧 REQUIRED ACTIONS:" "Yellow"
    
    if (-not $buildStatusOk) {
        Write-ColorOutput "   1. ❌ Fix CI/CD pipeline - all recent builds failing" "Red"
        Write-ColorOutput "      - Check GitHub Actions logs for latest errors" "Yellow"
        Write-ColorOutput "      - Resolve infrastructure/configuration issues" "Yellow"
        Write-ColorOutput "      - Retry deployment after fixes" "Yellow"
    }
    
    if (-not $infrastructureOk) {
        Write-ColorOutput "   2. ❌ Deploy infrastructure - no running instances found" "Red" 
        Write-ColorOutput "      - Run: gh workflow run 'Deploy OpenClaw to EC2' --field action=apply" "Yellow"
    }
    
    if (-not $servicesOk -and $infrastructureOk) {
        Write-ColorOutput "   3. ❌ Fix OpenClaw services - instances running but services not responding" "Red"
        Write-ColorOutput "      - SSH to instances and debug service startup" "Yellow"
        Write-ColorOutput "      - Check PM2 status and restart services if needed" "Yellow"
    }
}

Write-Host ""
Write-ColorOutput "📊 VALIDATION COMPLETE" "Blue"

# Return exit code for automation
if ($overallSuccess) {
    exit 0
} else {
    exit 1
}