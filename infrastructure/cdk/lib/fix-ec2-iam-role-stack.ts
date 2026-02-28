import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';

export class FixEC2IamRoleStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // =====================================================
    // CRITICAL FIX: Add IAM role to existing EC2 instance
    // =====================================================
    
    // Create IAM role with SSM permissions
    const ec2SSMRole = new iam.Role(this, 'OpenClawEC2SSMRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for OpenClaw EC2 instance with SSM management permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // Create instance profile - FIXED: Use CfnInstanceProfile instead of InstanceProfile
    const instanceProfile = new iam.CfnInstanceProfile(this, 'OpenClawEC2InstanceProfile', {
      roles: [ec2SSMRole.roleName],
    });

    // Output the instance profile ARN for attachment
    new cdk.CfnOutput(this, 'InstanceProfileArn', {
      value: instanceProfile.attrArn,
      description: 'Instance Profile ARN to attach to OpenClaw EC2',
    });

    new cdk.CfnOutput(this, 'RoleArn', {
      value: ec2SSMRole.roleArn,
      description: 'IAM Role ARN for OpenClaw EC2',
    });

    new cdk.CfnOutput(this, 'InstanceProfileName', {
      value: instanceProfile.ref,
      description: 'Instance Profile Name for attachment',
    });

    // Note: The actual attachment will be done via CLI in GitHub Actions
    // because CDK cannot modify existing EC2 instances directly
  }
}