# Quick Local OpenClaw Setup Script
# Run this to test OpenClaw locally on your machine

Write-Host "🚀 Setting up Local OpenClaw..." -ForegroundColor Blue

# Check if Node.js is installed
try {
    $nodeVersion = node --version
    Write-Host "✅ Node.js found: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Node.js not found!" -ForegroundColor Red
    Write-Host "💡 Please install Node.js LTS from: https://nodejs.org/" -ForegroundColor Yellow
    Write-Host "   Then run this script again." -ForegroundColor Yellow
    exit 1
}

# Check if OpenClaw is installed
try {
    $openclawVersion = openclaw --version
    Write-Host "✅ OpenClaw found: $openclawVersion" -ForegroundColor Green
} catch {
    Write-Host "📦 Installing OpenClaw globally..." -ForegroundColor Yellow
    try {
        npm install -g openclaw
        Write-Host "✅ OpenClaw installed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to install OpenClaw" -ForegroundColor Red
        Write-Host "💡 Try running as Administrator or check npm permissions" -ForegroundColor Yellow
        exit 1
    }
}

# Create local workspace
$workspaceDir = "openclaw-local-test"
if (-not (Test-Path $workspaceDir)) {
    New-Item -ItemType Directory -Path $workspaceDir | Out-Null
    Write-Host "📁 Created workspace directory: $workspaceDir" -ForegroundColor Green
} else {
    Write-Host "📁 Using existing workspace: $workspaceDir" -ForegroundColor Green
}

Set-Location $workspaceDir

# Create config file
$config = @{
    server = @{
        port = 8080
        host = "127.0.0.1"
    }
    gateway = @{
        enabled = $true
        port = 8080
        cors = @{
            enabled = $true
            origin = "*"
        }
    }
    logging = @{
        level = "info"
        file = "./openclaw.log"
    }
    workspace = "./workspace"
}

$configJson = $config | ConvertTo-Json -Depth 4
$configJson | Out-File -FilePath "config.json" -Encoding UTF8

Write-Host "⚙️ Created OpenClaw configuration" -ForegroundColor Green

# Create workspace directory
if (-not (Test-Path "workspace")) {
    New-Item -ItemType Directory -Path "workspace" | Out-Null
}

Write-Host ""
Write-Host "🎉 Local OpenClaw setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "🚀 To start OpenClaw:" -ForegroundColor Blue
Write-Host "   openclaw gateway start --config config.json" -ForegroundColor Cyan
Write-Host ""
Write-Host "🌐 Then access OpenClaw at:" -ForegroundColor Blue
Write-Host "   http://localhost:8080" -ForegroundColor Cyan
Write-Host ""
Write-Host "🛑 To stop OpenClaw:" -ForegroundColor Blue
Write-Host "   Press Ctrl+C in the terminal where it's running" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 Current directory: $(Get-Location)" -ForegroundColor Blue