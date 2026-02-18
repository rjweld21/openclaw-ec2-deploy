#!/usr/bin/env node

require('dotenv').config();
const AWS = require('aws-sdk');
const chalk = require('chalk');

async function validateAWSCredentials() {
    console.log(chalk.blue('🔍 Validating AWS credentials...'));
    
    // Set AWS credentials from environment variables
    const accessKeyId = process.env.AWS_ACCESS_KEY_ID;
    const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
    const region = process.env.AWS_REGION || 'us-east-1';
    
    if (!accessKeyId || !secretAccessKey) {
        console.error(chalk.red('❌ Missing AWS credentials in environment variables'));
        console.error(chalk.yellow('Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY'));
        process.exit(1);
    }
    
    console.log(chalk.gray(`Access Key ID: ${accessKeyId}`));
    console.log(chalk.gray(`Region: ${region}`));
    
    // Configure AWS SDK
    AWS.config.update({
        accessKeyId: accessKeyId,
        secretAccessKey: secretAccessKey,
        region: region
    });
    
    try {
        // Test STS GetCallerIdentity
        console.log(chalk.blue('Testing STS GetCallerIdentity...'));
        const sts = new AWS.STS();
        const identity = await sts.getCallerIdentity().promise();
        
        console.log(chalk.green('✅ AWS credentials are valid!'));
        console.log(chalk.gray(`User ARN: ${identity.Arn}`));
        console.log(chalk.gray(`Account ID: ${identity.Account}`));
        console.log(chalk.gray(`User ID: ${identity.UserId}`));
        
        // Test EC2 permissions
        console.log(chalk.blue('\nTesting EC2 permissions...'));
        const ec2 = new AWS.EC2();
        
        try {
            await ec2.describeRegions().promise();
            console.log(chalk.green('✅ EC2 permissions verified'));
        } catch (ec2Error) {
            console.warn(chalk.yellow('⚠️  EC2 permissions may be limited:'), ec2Error.message);
        }
        
        // Test IAM permissions
        console.log(chalk.blue('\nTesting IAM permissions...'));
        const iam = new AWS.IAM();
        
        try {
            await iam.listRoles({ MaxItems: 1 }).promise();
            console.log(chalk.green('✅ IAM permissions verified'));
        } catch (iamError) {
            console.warn(chalk.yellow('⚠️  IAM permissions may be limited:'), iamError.message);
        }
        
        console.log(chalk.green('\n🎉 AWS validation complete!'));
        
    } catch (error) {
        console.error(chalk.red('❌ AWS credential validation failed:'));
        console.error(chalk.red(error.message));
        
        if (error.code === 'InvalidUserID.NotFound' || error.code === 'SignatureDoesNotMatch') {
            console.error(chalk.red('\n💡 This suggests the AWS_SECRET_ACCESS_KEY is invalid or doesn\'t match the ACCESS_KEY_ID'));
        } else if (error.code === 'UnauthorizedOperation') {
            console.error(chalk.red('\n💡 Credentials are valid but lack required permissions'));
        }
        
        process.exit(1);
    }
}

if (require.main === module) {
    validateAWSCredentials().catch(console.error);
}

module.exports = { validateAWSCredentials };