#!/usr/bin/env node

require('dotenv').config();
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const chalk = require('chalk');
const { validateAWSCredentials } = require('./validate-aws');

class Deployer {
    constructor() {
        this.terraformDir = path.join(__dirname, '..', 'terraform');
    }

    async runCommand(command, args = [], options = {}) {
        return new Promise((resolve, reject) => {
            console.log(chalk.blue(`Running: ${command} ${args.join(' ')}`));
            
            const proc = spawn(command, args, {
                stdio: 'inherit',
                cwd: options.cwd || process.cwd(),
                env: { ...process.env, ...options.env }
            });

            proc.on('close', (code) => {
                if (code === 0) {
                    resolve(code);
                } else {
                    reject(new Error(`Command failed with exit code ${code}`));
                }
            });

            proc.on('error', (error) => {
                reject(error);
            });
        });
    }

    async checkTerraformInstalled() {
        try {
            await this.runCommand('terraform', ['version']);
            console.log(chalk.green('✅ Terraform is installed'));
        } catch (error) {
            console.error(chalk.red('❌ Terraform is not installed or not in PATH'));
            console.error(chalk.yellow('Please install Terraform: https://www.terraform.io/downloads'));
            process.exit(1);
        }
    }

    async initializeTerraform() {
        console.log(chalk.blue('\n📦 Initializing Terraform...'));
        
        if (!fs.existsSync(this.terraformDir)) {
            throw new Error(`Terraform directory not found: ${this.terraformDir}`);
        }

        await this.runCommand('terraform', ['init'], {
            cwd: this.terraformDir,
            env: {
                AWS_ACCESS_KEY_ID: process.env.AWS_ACCESS_KEY_ID,
                AWS_SECRET_ACCESS_KEY: process.env.AWS_SECRET_ACCESS_KEY,
                AWS_REGION: process.env.AWS_REGION
            }
        });
        
        console.log(chalk.green('✅ Terraform initialized'));
    }

    async planDeployment() {
        console.log(chalk.blue('\n📋 Planning deployment...'));
        
        await this.runCommand('terraform', ['plan'], {
            cwd: this.terraformDir,
            env: {
                AWS_ACCESS_KEY_ID: process.env.AWS_ACCESS_KEY_ID,
                AWS_SECRET_ACCESS_KEY: process.env.AWS_SECRET_ACCESS_KEY,
                AWS_REGION: process.env.AWS_REGION,
                TF_VAR_aws_region: process.env.AWS_REGION,
                TF_VAR_instance_type: process.env.INSTANCE_TYPE || 't3.micro',
                TF_VAR_key_pair_name: process.env.KEY_PAIR_NAME || 'openclaw-ec2-key'
            }
        });
        
        console.log(chalk.green('✅ Deployment plan created'));
    }

    async applyDeployment() {
        console.log(chalk.blue('\n🚀 Applying deployment...'));
        
        await this.runCommand('terraform', ['apply', '-auto-approve'], {
            cwd: this.terraformDir,
            env: {
                AWS_ACCESS_KEY_ID: process.env.AWS_ACCESS_KEY_ID,
                AWS_SECRET_ACCESS_KEY: process.env.AWS_SECRET_ACCESS_KEY,
                AWS_REGION: process.env.AWS_REGION,
                TF_VAR_aws_region: process.env.AWS_REGION,
                TF_VAR_instance_type: process.env.INSTANCE_TYPE || 't3.micro',
                TF_VAR_key_pair_name: process.env.KEY_PAIR_NAME || 'openclaw-ec2-key'
            }
        });
        
        console.log(chalk.green('✅ Deployment completed!'));
    }

    async savePrivateKey() {
        console.log(chalk.blue('\n🔐 Saving private key...'));
        
        try {
            const { stdout } = await this.runCommand('terraform', ['output', '-raw', 'private_key_pem'], {
                cwd: this.terraformDir
            });
            
            const keyPath = path.join(__dirname, '..', 'openclaw-ec2-key.pem');
            fs.writeFileSync(keyPath, stdout, { mode: 0o600 });
            console.log(chalk.green(`✅ Private key saved to: ${keyPath}`));
            
        } catch (error) {
            console.warn(chalk.yellow('⚠️  Could not save private key automatically'));
            console.log(chalk.gray('You can retrieve it manually with: terraform output private_key_pem'));
        }
    }

    async getDeploymentInfo() {
        console.log(chalk.blue('\n📊 Retrieving deployment information...'));
        
        try {
            const commands = [
                ['output', 'instance_public_ip'],
                ['output', 'instance_public_dns'],
                ['output', 'ssh_connection_command']
            ];

            for (const [command, ...args] of commands) {
                await this.runCommand('terraform', [command, ...args], {
                    cwd: this.terraformDir
                });
            }
            
        } catch (error) {
            console.warn(chalk.yellow('⚠️  Could not retrieve all deployment information'));
        }
    }

    async deploy() {
        try {
            console.log(chalk.blue('🚀 Starting OpenClaw EC2 deployment...\n'));

            // Step 1: Validate AWS credentials
            await validateAWSCredentials();

            // Step 2: Check Terraform installation
            await this.checkTerraformInstalled();

            // Step 3: Initialize Terraform
            await this.initializeTerraform();

            // Step 4: Plan deployment
            await this.planDeployment();

            // Step 5: Apply deployment
            await this.applyDeployment();

            // Step 6: Save private key
            await this.savePrivateKey();

            // Step 7: Get deployment info
            await this.getDeploymentInfo();

            console.log(chalk.green('\n🎉 Deployment completed successfully!'));
            console.log(chalk.yellow('\nNext steps:'));
            console.log(chalk.gray('1. Wait a few minutes for the instance to fully initialize'));
            console.log(chalk.gray('2. Use the SSH command above to connect to your instance'));
            console.log(chalk.gray('3. Check the health endpoint at http://<public-ip>:8080/health'));

        } catch (error) {
            console.error(chalk.red('\n❌ Deployment failed:'));
            console.error(chalk.red(error.message));
            process.exit(1);
        }
    }
}

if (require.main === module) {
    const deployer = new Deployer();
    deployer.deploy();
}

module.exports = { Deployer };