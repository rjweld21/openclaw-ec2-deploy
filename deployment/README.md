# Deployment

Application deployment scripts and configurations.

## Contents
- `install.sh` - OpenClaw Gateway installation script
- `config/` - OpenClaw configuration templates
- `systemd/` - Service definitions for auto-start
- `nginx/` - Reverse proxy configuration
- `pm2/` - Process manager configuration

## Deployment Process
1. Provision EC2 infrastructure
2. Install Node.js runtime and dependencies  
3. Deploy OpenClaw Gateway
4. Configure reverse proxy and SSL
5. Set up monitoring and health checks
6. Start services and verify operation

## Status
🚧 In development