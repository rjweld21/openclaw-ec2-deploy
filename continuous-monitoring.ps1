# Continuous OpenClaw Deployment Monitoring System
# Monitors task progress every 5 minutes and spawns agents as needed

param(
    [Parameter(Mandatory=$false)]
    [int]$IntervalMinutes = 5,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxIterations = 100,
    
    [Parameter(Mandatory=$false)]
    [switch]$OneShot
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

function Get-TaskStatus {
    if (-not (Test-Path "TASK-TRACKER.md")) {
        return @{ Error = "Task tracker not found" }
    }
    
    $content = Get-Content "TASK-TRACKER.md" -Raw
    
    # Count task statuses
    $totalTasks = ($content | Select-String -Pattern "- \[ \].*\*\*\d+\.\d+\.\d+\*\*" -AllMatches).Matches.Count
    $completeTasks = ($content | Select-String -Pattern "- \[ \] ✅.*\*\*\d+\.\d+\.\d+\*\*" -AllMatches).Matches.Count
    $failedTasks = ($content | Select-String -Pattern "- \[ \] ❌.*\*\*\d+\.\d+\.\d+\*\*" -AllMatches).Matches.Count  
    $inProgressTasks = ($content | Select-String -Pattern "- \[ \] 🔵.*\*\*\d+\.\d+\.\d+\*\*" -AllMatches).Matches.Count
    $pendingTasks = $totalTasks - $completeTasks - $failedTasks - $inProgressTasks
    
    # Get current iteration info
    $currentIteration = if ($content -match "### Iteration (\d+).*🔵 In Progress") { [int]$matches[1] } else { 0 }
    
    # Check for active agents (by looking for recent activity)
    $lastUpdateTime = (Get-Item "TASK-TRACKER.md").LastWriteTime
    $timeSinceUpdate = (Get-Date) - $lastUpdateTime
    
    return @{
        TotalTasks = $totalTasks
        CompleteTasks = $completeTasks
        FailedTasks = $failedTasks
        InProgressTasks = $inProgressTasks  
        PendingTasks = $pendingTasks
        CurrentIteration = $currentIteration
        LastUpdateMinutesAgo = [Math]::Round($timeSinceUpdate.TotalMinutes, 1)
        TaskTrackerPath = (Resolve-Path "TASK-TRACKER.md").Path
    }
}

function Test-AgentsRunning {
    # Check for active subagent processes by looking at recent activity
    $status = Get-TaskStatus
    
    # Consider agents "running" if task tracker was updated recently (within interval)
    $agentsActive = $status.LastUpdateMinutesAgo -lt ($IntervalMinutes + 2)
    
    return @{
        Active = $agentsActive
        LastUpdateMinutesAgo = $status.LastUpdateMinutesAgo
        RecentActivity = $agentsActive
    }
}

function Test-DeploymentComplete {
    try {
        # Run comprehensive validation
        $validationResult = .\validate-complete-deployment.ps1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Spawn-ContinuationAgent {
    param([string]$Reason)
    
    Write-ColorOutput "🚀 Spawning continuation agent: $Reason" "Yellow"
    
    $taskStatus = Get-TaskStatus
    
    $agentTask = @"
🔄 CONTINUATION DEBUGGING AGENT - Iteration $($taskStatus.CurrentIteration + 1)

**MONITORING SYSTEM DETECTED**: $Reason

**CURRENT TASK STATUS**:
- Total Tasks: $($taskStatus.TotalTasks)
- Complete: $($taskStatus.CompleteTasks) ✅
- Failed: $($taskStatus.FailedTasks) ❌  
- In Progress: $($taskStatus.InProgressTasks) 🔵
- Pending: $($taskStatus.PendingTasks) 🟡

**YOUR MISSION**:
1. **Analyze Current State**: Review openclaw-ec2-deploy/TASK-TRACKER.md to understand current status
2. **Continue Debugging**: Pick up where previous agent left off
3. **Focus on Blockers**: Identify and resolve current deployment blockers
4. **Update Progress**: Update TASK-TRACKER.md with your progress
5. **Complete Tasks**: Work systematically through remaining task list items

**PRIORITY FOCUS**:
- Fix CI/CD pipeline failures (all recent builds failing)
- Ensure successful Terraform deployment
- Validate OpenClaw services are running
- Complete end-to-end validation

**SUCCESS CRITERIA**: 
- Working OpenClaw deployment at http://instance-ip:8080
- validate-complete-deployment.ps1 returns success
- Task list phases marked complete

**UPDATE TASK TRACKER** with your progress and commit all fixes.

Start immediately - continuous system expects progress.
"@

    try {
        # Spawn new debugging agent
        $result = Start-Process -FilePath "openclaw" -ArgumentList @(
            "sessions", "spawn", 
            "--runtime", "subagent",
            "--agent-id", "ai-architect", 
            "--mode", "run",
            "--task", $agentTask,
            "--label", "continuation-agent-$((Get-Date).ToString('HHmm'))",
            "--timeout", "3600"
        ) -NoNewWindow -PassThru -Wait
        
        if ($result.ExitCode -eq 0) {
            Write-ColorOutput "✅ Continuation agent spawned successfully" "Green"
            return $true
        } else {
            Write-ColorOutput "❌ Failed to spawn continuation agent" "Red"
            return $false
        }
    } catch {
        Write-ColorOutput "❌ Error spawning agent: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Start-MonitoringCycle {
    $iteration = 1
    
    Write-ColorOutput "🔍 Starting Continuous OpenClaw Deployment Monitoring" "Blue"
    Write-Host "============================================================"
    Write-ColorOutput "Monitoring interval: $IntervalMinutes minutes" "Cyan"
    Write-ColorOutput "Maximum iterations: $MaxIterations" "Cyan"
    Write-ColorOutput "Start time: $(Get-Date)" "Cyan"
    Write-Host ""
    
    while ($iteration -le $MaxIterations) {
        Write-ColorOutput "🔍 MONITORING CYCLE $iteration - $(Get-Date)" "Blue" 
        Write-Host "----------------------------------------"
        
        # Check if deployment is complete
        if (Test-DeploymentComplete) {
            Write-ColorOutput "🎉 DEPLOYMENT COMPLETE - SUCCESS!" "Green"
            Write-ColorOutput "✅ All validation checks passed" "Green"
            Write-ColorOutput "🌐 OpenClaw deployment is fully working" "Green"
            break
        }
        
        # Get current task status
        $taskStatus = Get-TaskStatus
        if ($taskStatus.Error) {
            Write-ColorOutput "❌ Error reading task status: $($taskStatus.Error)" "Red"
        } else {
            Write-ColorOutput "📊 Task Status: $($taskStatus.CompleteTasks)/$($taskStatus.TotalTasks) complete" "Yellow"
            Write-ColorOutput "   ✅ Complete: $($taskStatus.CompleteTasks)" "Green"
            Write-ColorOutput "   ❌ Failed: $($taskStatus.FailedTasks)" "Red"  
            Write-ColorOutput "   🔵 In Progress: $($taskStatus.InProgressTasks)" "Blue"
            Write-ColorOutput "   🟡 Pending: $($taskStatus.PendingTasks)" "Yellow"
            Write-ColorOutput "   📝 Last update: $($taskStatus.LastUpdateMinutesAgo) minutes ago" "Cyan"
        }
        
        # Check if agents are running
        $agentStatus = Test-AgentsRunning
        if ($agentStatus.Active) {
            Write-ColorOutput "🔵 Agents appear to be active (recent task tracker updates)" "Green"
        } else {
            Write-ColorOutput "⚠️ No active agents detected!" "Yellow"
            Write-ColorOutput "   Last task tracker update: $($agentStatus.LastUpdateMinutesAgo) minutes ago" "Yellow"
            
            if ($agentStatus.LastUpdateMinutesAgo -gt ($IntervalMinutes * 2)) {
                Write-ColorOutput "🚨 System appears stalled - spawning continuation agent" "Red"
                
                if (Spawn-ContinuationAgent -Reason "No agent activity detected for $($agentStatus.LastUpdateMinutesAgo) minutes") {
                    Write-ColorOutput "✅ Continuation agent spawned" "Green"
                } else {
                    Write-ColorOutput "❌ Failed to spawn continuation agent" "Red"
                }
            }
        }
        
        # Check for completion conditions
        if ($taskStatus.CompleteTasks -eq $taskStatus.TotalTasks) {
            Write-ColorOutput "🎯 All tasks marked complete - running final validation" "Yellow"
            
            if (Test-DeploymentComplete) {
                Write-ColorOutput "🎉 FULL SUCCESS - All tasks complete and deployment working!" "Green"
                break
            } else {
                Write-ColorOutput "⚠️ Tasks marked complete but validation failing - spawning verification agent" "Yellow"
                Spawn-ContinuationAgent -Reason "Tasks complete but validation fails"
            }
        }
        
        if ($OneShot) {
            Write-ColorOutput "🔍 One-shot monitoring complete" "Blue"
            break
        }
        
        Write-Host ""
        Write-ColorOutput "⏳ Waiting $IntervalMinutes minutes until next check..." "Cyan"
        Start-Sleep -Seconds ($IntervalMinutes * 60)
        
        $iteration++
    }
    
    if ($iteration -gt $MaxIterations) {
        Write-ColorOutput "⚠️ Maximum iterations reached - monitoring stopped" "Yellow"
        Write-ColorOutput "Manual intervention may be required" "Yellow"
    }
    
    Write-ColorOutput "📊 Monitoring session complete: $(Get-Date)" "Blue"
}

# Main execution
try {
    Set-Location (Split-Path -Parent $PSScriptRoot)
    
    if (-not (Test-Path "openclaw-ec2-deploy")) {
        Write-ColorOutput "❌ openclaw-ec2-deploy directory not found" "Red"
        exit 1
    }
    
    Set-Location "openclaw-ec2-deploy"
    
    Start-MonitoringCycle
    
} catch {
    Write-ColorOutput "❌ Monitoring error: $($_.Exception.Message)" "Red"
    exit 1
}