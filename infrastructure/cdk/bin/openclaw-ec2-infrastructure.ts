#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { OpenClawNginxStack } from '../lib/openclaw-nginx-stack';
import { FixEC2IamRoleStack } from '../lib/fix-ec2-iam-role-stack';

const app = new cdk.App();

// IAM Role Fix Stack (deploy first)
new FixEC2IamRoleStack(app, 'OpenClawEC2IamFixStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// nginx HTTPS Proxy Stack (deploy after IAM fix)
new OpenClawNginxStack(app, 'OpenClawNginxProxyStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});