#!/usr/bin/env python3
"""
OpenClaw Deployment Status Checker
Monitors GitHub Actions and AWS infrastructure status
"""

import os
import sys
import json
import time
import requests
from datetime import datetime, timedelta

def check_github_actions(repo="rjweld21/openclaw-ec2-deploy"):
    """Check latest GitHub Actions run status"""
    try:
        url = f"https://api.github.com/repos/{repo}/actions/runs"
        response = requests.get(url)
        
        if response.status_code == 200:
            data = response.json()
            runs = data.get('workflow_runs', [])
            
            if runs:
                latest_run = runs[0]
                return {
                    'status': latest_run['status'],
                    'conclusion': latest_run.get('conclusion'),
                    'created_at': latest_run['created_at'],
                    'html_url': latest_run['html_url'],
                    'run_number': latest_run['run_number']
                }
        
        return None
    except Exception as e:
        print(f"Error checking GitHub Actions: {e}")
        return None

def check_aws_infrastructure():
    """Check AWS infrastructure status using AWS CLI"""
    try:
        import subprocess
        
        # Check Auto Scaling Group
        result = subprocess.run([
            'aws', 'autoscaling', 'describe-auto-scaling-groups',
            '--auto-scaling-group-names', 'openclaw-dev-asg',
            '--query', 'AutoScalingGroups[0].{Status:HealthCheckType,Instances:length(Instances),Desired:DesiredCapacity}'
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            asg_data = json.loads(result.stdout)
            
            # Check Load Balancer
            lb_result = subprocess.run([
                'aws', 'elbv2', 'describe-load-balancers',
                '--names', 'openclaw-dev-alb',
                '--query', 'LoadBalancers[0].{State:State.Code,DNS:DNSName}'
            ], capture_output=True, text=True)
            
            lb_data = {}
            if lb_result.returncode == 0:
                lb_data = json.loads(lb_result.stdout)
            
            return {
                'asg': asg_data,
                'load_balancer': lb_data
            }
    except Exception as e:
        print(f"Error checking AWS infrastructure: {e}")
    
    return None

def check_application_health(url=None):
    """Check application health endpoint"""
    if not url:
        # Try to get ALB DNS name
        try:
            import subprocess
            result = subprocess.run([
                'aws', 'elbv2', 'describe-load-balancers',
                '--names', 'openclaw-dev-alb',
                '--query', 'LoadBalancers[0].DNSName',
                '--output', 'text'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                dns_name = result.stdout.strip()
                url = f"http://{dns_name}/health"
        except:
            pass
    
    if not url:
        return None
    
    try:
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            return {
                'status': 'healthy',
                'response_time': response.elapsed.total_seconds(),
                'data': response.json() if response.headers.get('content-type', '').startswith('application/json') else response.text
            }
        else:
            return {
                'status': 'unhealthy',
                'status_code': response.status_code,
                'response_time': response.elapsed.total_seconds()
            }
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e)
        }

def main():
    """Main monitoring function"""
    print("🚀 OpenClaw Deployment Monitor")
    print("=" * 50)
    
    # Check GitHub Actions
    print("\n📋 GitHub Actions Status:")
    gh_status = check_github_actions()
    if gh_status:
        print(f"  Run #{gh_status['run_number']}: {gh_status['status']}")
        if gh_status['conclusion']:
            print(f"  Conclusion: {gh_status['conclusion']}")
        print(f"  Started: {gh_status['created_at']}")
        print(f"  URL: {gh_status['html_url']}")
    else:
        print("  ❌ Could not fetch GitHub Actions status")
    
    # Check AWS Infrastructure
    print("\n🏗️  AWS Infrastructure Status:")
    aws_status = check_aws_infrastructure()
    if aws_status:
        asg = aws_status.get('asg', {})
        lb = aws_status.get('load_balancer', {})
        
        print(f"  Auto Scaling Group: {asg.get('Instances', 0)}/{asg.get('Desired', 0)} instances")
        if lb:
            print(f"  Load Balancer: {lb.get('State', 'unknown')} - {lb.get('DNS', 'N/A')}")
    else:
        print("  ❌ Could not fetch AWS infrastructure status")
    
    # Check Application Health
    print("\n💚 Application Health:")
    health = check_application_health()
    if health:
        if health['status'] == 'healthy':
            print(f"  ✅ Application is healthy (response: {health['response_time']:.2f}s)")
            if 'data' in health:
                print(f"  Data: {health['data']}")
        else:
            print(f"  ❌ Application unhealthy: {health}")
    else:
        print("  ⏳ Application URL not available yet")
    
    print("\n" + "=" * 50)
    print(f"Check completed at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--continuous":
        print("Starting continuous monitoring (press Ctrl+C to stop)...")
        try:
            while True:
                main()
                time.sleep(30)  # Check every 30 seconds
        except KeyboardInterrupt:
            print("\nMonitoring stopped.")
    else:
        main()