#!/usr/bin/env node

require('dotenv').config();
const AWS = require('aws-sdk');
const chalk = require('chalk');
const path = require('path');
const { spawn } = require('child_process');

class StatusChecker {
    constructor() {
        this.terraformDir = path.join(__dirname, '..', 'terraform');
        
        // Configure AWS
        AWS.config.update({
            accessKeyId: process.env.AWS_ACCESS_KEY_ID,
            secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
            region: process.env.AWS_REGION || 'us-east-1'
        });
        
        this.ec2 = new AWS.EC2();
    }

    async runCommand(command, args = [], options = {}) {
        return new Promise((resolve, reject) => {
            const proc = spawn(command, args, {
                stdio: 'pipe',
                cwd: options.cwd || process.cwd(),
                env: { ...process.env, ...options.env }
            });

            let stdout = '';
            let stderr = '';

            proc.stdout.on('data', (data) => {
                stdout += data.toString();
            });

            proc.stderr.on('data', (data) => {
                stderr += data.toString();
            });

            proc.on('close', (code) => {
                if (code === 0) {
                    resolve({ stdout: stdout.trim(), stderr: stderr.trim() });
                } else {
                    reject(new Error(`Command failed with exit code ${code}: ${stderr}`));
                }
            });

            proc.on('error', (error) => {
                reject(error);
            });
        });
    }

    async getTerraformOutputs() {
        try {
            const outputs = {};
            const outputNames = ['instance_id', 'instance_public_ip', 'instance_public_dns'];

            for (const outputName of outputNames) {
                try {
                    const result = await this.runCommand('terraform', ['output', '-raw', outputName], {
                        cwd: this.terraformDir
                    });
                    outputs[outputName] = result.stdout;
                } catch (error) {
                    outputs[outputName] = null;
                }
            }

            return outputs;
        } catch (error) {
            return {};
        }
    }

    async checkInstanceStatus(instanceId) {
        try {
            const result = await this.ec2.describeInstances({
                InstanceIds: [instanceId]
            }).promise();

            if (result.Reservations.length > 0 && result.Reservations[0].Instances.length > 0) {
                const instance = result.Reservations[0].Instances[0];
                return {
                    state: instance.State.Name,
                    launchTime: instance.LaunchTime,
                    instanceType: instance.InstanceType,
                    publicIp: instance.PublicIpAddress,
                    privateIp: instance.PrivateIpAddress,
                    keyName: instance.KeyName
                };
            }
        } catch (error) {
            console.error(chalk.yellow(`⚠️  Could not get instance status: ${error.message}`));
        }
        return null;
    }

    async checkHealthEndpoint(publicIp) {
        try {
            const https = require('http');
            
            return new Promise((resolve) => {
                const req = https.get(`http://${publicIp}:8080/health`, { timeout: 10000 }, (res) => {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => {
                        try {
                            const healthData = JSON.parse(data);
                            resolve({
                                status: 'healthy',
                                data: healthData,
                                httpStatus: res.statusCode
                            });
                        } catch (error) {
                            resolve({
                                status: 'unhealthy',
                                error: 'Invalid JSON response',
                                httpStatus: res.statusCode
                            });
                        }
                    });
                });

                req.on('error', (error) => {
                    resolve({
                        status: 'unreachable',
                        error: error.message
                    });
                });

                req.on('timeout', () => {
                    req.destroy();
                    resolve({
                        status: 'timeout',
                        error: 'Request timed out'
                    });
                });
            });
        } catch (error) {
            return {
                status: 'error',
                error: error.message
            };
        }
    }

    async checkStatus() {
        console.log(chalk.blue('📊 Checking OpenClaw EC2 deployment status...\n'));

        // Get Terraform outputs
        const outputs = await this.getTerraformOutputs();
        
        if (!outputs.instance_id) {
            console.log(chalk.red('❌ No deployment found'));
            console.log(chalk.gray('Run `npm run deploy` to create a new deployment'));
            return;
        }

        console.log(chalk.green('✅ Deployment found'));
        console.log(chalk.gray(`Instance ID: ${outputs.instance_id}`));
        
        if (outputs.instance_public_ip) {
            console.log(chalk.gray(`Public IP: ${outputs.instance_public_ip}`));
        }
        
        if (outputs.instance_public_dns) {
            console.log(chalk.gray(`Public DNS: ${outputs.instance_public_dns}`));
        }

        // Check instance status
        console.log(chalk.blue('\n🔍 Checking instance status...'));
        const instanceStatus = await this.checkInstanceStatus(outputs.instance_id);
        
        if (instanceStatus) {
            const stateColor = instanceStatus.state === 'running' ? 'green' : 
                             instanceStatus.state === 'stopped' ? 'red' : 'yellow';
            
            console.log(chalk[stateColor](`State: ${instanceStatus.state}`));
            console.log(chalk.gray(`Instance Type: ${instanceStatus.instanceType}`));
            console.log(chalk.gray(`Launch Time: ${instanceStatus.launchTime}`));
            
            if (instanceStatus.publicIp) {
                console.log(chalk.gray(`Public IP: ${instanceStatus.publicIp}`));
            }
            
            if (instanceStatus.privateIp) {
                console.log(chalk.gray(`Private IP: ${instanceStatus.privateIp}`));
            }
            
            if (instanceStatus.keyName) {
                console.log(chalk.gray(`Key Pair: ${instanceStatus.keyName}`));
            }

            // Check health endpoint if instance is running
            if (instanceStatus.state === 'running' && instanceStatus.publicIp) {
                console.log(chalk.blue('\n🏥 Checking health endpoint...'));
                const health = await this.checkHealthEndpoint(instanceStatus.publicIp);
                
                if (health.status === 'healthy') {
                    console.log(chalk.green(`✅ Health check passed (HTTP ${health.httpStatus})`));
                    if (health.data) {
                        console.log(chalk.gray(`Application uptime: ${Math.round(health.data.uptime)} seconds`));
                        console.log(chalk.gray(`Last check: ${health.data.timestamp}`));
                    }
                    console.log(chalk.gray(`Health URL: http://${instanceStatus.publicIp}:8080/health`));
                } else {
                    console.log(chalk.red(`❌ Health check failed: ${health.status}`));
                    if (health.error) {
                        console.log(chalk.red(`Error: ${health.error}`));
                    }
                }
            }

        } else {
            console.log(chalk.red('❌ Could not retrieve instance status'));
        }

        // SSH connection info
        if (outputs.instance_public_ip) {
            console.log(chalk.blue('\n🔐 SSH Connection:'));
            console.log(chalk.gray(`ssh -i openclaw-ec2-key.pem ubuntu@${outputs.instance_public_ip}`));
        }

        console.log(chalk.blue('\n📋 Available commands:'));
        console.log(chalk.gray('• npm run deploy     - Deploy infrastructure'));
        console.log(chalk.gray('• npm run status     - Check deployment status'));
        console.log(chalk.gray('• npm run destroy    - Destroy infrastructure'));
        console.log(chalk.gray('• npm run validate-aws - Test AWS credentials'));
    }
}

if (require.main === module) {
    const checker = new StatusChecker();
    checker.checkStatus().catch(console.error);
}

module.exports = { StatusChecker };