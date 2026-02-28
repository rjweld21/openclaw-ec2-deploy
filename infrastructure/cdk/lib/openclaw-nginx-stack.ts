import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';

export class OpenClawNginxStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // =====================================================
    // Update existing OpenClaw EC2 with nginx HTTPS proxy
    // This adds nginx configuration to the existing EC2
    // =====================================================

    // Get existing OpenClaw EC2 instance
    const existingInstanceId = 'i-0f7b10ac4566c4ea4'; // openclaw-fixed

    // Create SSM document for nginx setup
    const nginxSetupDocument = new ssm.CfnDocument(this, 'OpenClawNginxSetup', {
      documentType: 'Command',
      documentFormat: 'YAML',
      content: {
        schemaVersion: '2.2',
        description: 'Install and configure nginx HTTPS proxy for OpenClaw',
        parameters: {
          instanceId: {
            type: 'String',
            description: 'EC2 Instance ID to configure'
          }
        },
        mainSteps: [
          {
            action: 'aws:runShellScript',
            name: 'installNginx',
            inputs: {
              timeoutSeconds: '300',
              runCommand: [
                '#!/bin/bash',
                'set -e',
                '',
                '# Install nginx',
                'sudo yum update -y',
                'sudo yum install -y nginx',
                '',
                '# Create SSL directory',
                'sudo mkdir -p /etc/nginx/ssl',
                '',
                '# Generate self-signed certificate with correct IP',
                'INSTANCE_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)',
                'sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\',
                '    -keyout /etc/nginx/ssl/openclaw.key \\',
                '    -out /etc/nginx/ssl/openclaw.crt \\',
                '    -subj "/C=US/ST=State/L=City/O=OpenClaw/CN=$INSTANCE_IP"',
                '',
                '# Create nginx configuration for OpenClaw HTTPS proxy',
                'sudo tee /etc/nginx/conf.d/openclaw.conf > /dev/null << EOF',
                '# Redirect HTTP to HTTPS',
                'server {',
                '    listen 80;',
                '    server_name _;',
                '    return 301 https://\\$server_name\\$request_uri;',
                '}',
                '',
                '# HTTPS proxy to OpenClaw',
                'server {',
                '    listen 443 ssl http2;',
                '    server_name _;',
                '',
                '    # SSL configuration',
                '    ssl_certificate /etc/nginx/ssl/openclaw.crt;',
                '    ssl_certificate_key /etc/nginx/ssl/openclaw.key;',
                '    ssl_protocols TLSv1.2 TLSv1.3;',
                '    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;',
                '    ssl_prefer_server_ciphers off;',
                '',
                '    # WebSocket and HTTP proxy configuration',
                '    location / {',
                '        proxy_pass http://localhost:8080;',
                '        proxy_http_version 1.1;',
                '        proxy_set_header Upgrade \\$http_upgrade;',
                '        proxy_set_header Connection "upgrade";',
                '        proxy_set_header Host \\$host;',
                '        proxy_set_header X-Real-IP \\$remote_addr;',
                '        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;',
                '        proxy_set_header X-Forwarded-Proto \\$scheme;',
                '        proxy_cache_bypass \\$http_upgrade;',
                '        proxy_read_timeout 86400;',
                '        proxy_connect_timeout 86400;',
                '        proxy_send_timeout 86400;',
                '',
                '        # CORS headers for WebSocket',
                '        add_header Access-Control-Allow-Origin "*" always;',
                '        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;',
                '        add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range" always;',
                '    }',
                '}',
                'EOF',
                '',
                '# Test nginx configuration',
                'sudo nginx -t',
                '',
                '# Enable and start nginx',
                'sudo systemctl enable nginx',
                'sudo systemctl restart nginx',
                '',
                '# Update firewall/security group (handled by CDK)',
                '',
                '# Verify nginx is running',
                'sudo systemctl status nginx --no-pager',
                '',
                '# Create health check script',
                'sudo tee /home/ec2-user/nginx-health-check.sh > /dev/null << EOF',
                '#!/bin/bash',
                'echo "=== nginx + OpenClaw Health Check ==="',
                'echo "nginx status: $(sudo systemctl is-active nginx)"',
                'echo "OpenClaw status: $(ps aux | grep -c openclaw-gateway || echo 0)"',
                'echo "HTTP->HTTPS redirect test:"',
                'curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "FAILED"',
                'echo "HTTPS test:"',
                'curl -s -o /dev/null -w "%{http_code}" -k https://localhost/ || echo "FAILED"',
                'echo "WebSocket test:"',
                'curl -s -o /dev/null -w "%{http_code}" -k -H "Upgrade: websocket" -H "Connection: Upgrade" https://localhost/ || echo "FAILED"',
                'echo "Setup completed: $(date)"',
                'EOF',
                '',
                'sudo chmod +x /home/ec2-user/nginx-health-check.sh',
                '',
                '# Run initial health check',
                '/home/ec2-user/nginx-health-check.sh',
                '',
                'echo "nginx HTTPS proxy setup completed successfully!"'
              ]
            }
          }
        ]
      }
    });

    // Output the SSM document name for GitHub Actions to use
    new cdk.CfnOutput(this, 'NginxSetupDocumentName', {
      value: nginxSetupDocument.ref,
      description: 'SSM Document name for nginx setup',
    });

    new cdk.CfnOutput(this, 'ExistingInstanceId', {
      value: existingInstanceId,
      description: 'Existing OpenClaw EC2 Instance ID to update',
    });

    // Create SSM parameter to store setup status
    new ssm.StringParameter(this, 'OpenClawNginxSetupStatus', {
      parameterName: '/openclaw/nginx/setup-status',
      stringValue: 'pending',
      description: 'OpenClaw nginx setup status',
    });
  }
}