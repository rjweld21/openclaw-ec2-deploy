#!/usr/bin/env node

require('dotenv').config();
const { spawn } = require('child_process');
const path = require('path');
const chalk = require('chalk');
const inquirer = require('inquirer');

class Destroyer {
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

    async confirmDestruction() {
        console.log(chalk.yellow('⚠️  WARNING: This will permanently destroy all AWS resources!'));
        console.log(chalk.gray('This includes:'));
        console.log(chalk.gray('• EC2 instance'));
        console.log(chalk.gray('• VPC and networking components'));
        console.log(chalk.gray('• Security groups'));
        console.log(chalk.gray('• Key pairs'));
        console.log(chalk.gray('• All data on the instance'));

        const answers = await inquirer.prompt([
            {
                type: 'confirm',
                name: 'confirmDestroy',
                message: 'Are you sure you want to destroy the infrastructure?',
                default: false
            }
        ]);

        return answers.confirmDestroy;
    }

    async destroy() {
        try {
            console.log(chalk.red('🗑️  Starting OpenClaw EC2 infrastructure destruction...\n'));

            // Confirm destruction
            const confirmed = await this.confirmDestruction();
            
            if (!confirmed) {
                console.log(chalk.yellow('Destruction cancelled.'));
                return;
            }

            console.log(chalk.blue('\n🗑️  Destroying infrastructure...'));
            
            await this.runCommand('terraform', ['destroy', '-auto-approve'], {
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

            console.log(chalk.green('\n✅ Infrastructure destroyed successfully!'));
            console.log(chalk.gray('\nAll AWS resources have been removed.'));
            console.log(chalk.gray('Local files (private keys, etc.) remain and can be cleaned up manually.'));

        } catch (error) {
            console.error(chalk.red('\n❌ Destruction failed:'));
            console.error(chalk.red(error.message));
            process.exit(1);
        }
    }
}

if (require.main === module) {
    const destroyer = new Destroyer();
    destroyer.destroy();
}

module.exports = { Destroyer };