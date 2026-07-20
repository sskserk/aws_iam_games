# AWS Marketplace Product Configuration Guide

## Overview

This guide covers the initial AWS Marketplace launch of Awide PostgreSQL Suite. It is intentionally high level and focuses on the decisions required during CloudFormation deployment.

After the stack reaches `CREATE_COMPLETE`, continue with `configure.md` for RDS connectivity and extended analytics setup.

## What the Deployment Creates

The Marketplace template provisions the base product environment:

- VPC, subnets, internet gateway, and routing
- Security group for the application host
- EC2 instance running Awide PostgreSQL Suite
- Private Route 53 hosted zone and DNS record
- EC2 IAM role and instance profile
- S3 bucket for logs
- Firehose IAM role for log delivery

## Before Launch

Confirm the target AWS account and region, required permissions for VPC, EC2, IAM, Route 53, S3, and CloudFormation, and whether you need custom CIDR ranges, a custom AMI, or a specific Awide Suite version.

## Launch Steps

1. Open the product in AWS Marketplace and subscribe if needed.
2. Choose **Continue to Configuration**, select the product version, then choose **Continue to Launch**.
3. Launch through **CloudFormation**.
4. Enter a stack name and review the template parameters.
5. Acknowledge IAM resource creation if prompted.
6. Create the stack and monitor it until `CREATE_COMPLETE`.

## Parameters to Review

Most deployments can use the defaults. Review these values before launch:

- `VpcCidr`, `Subnet1Cidr`, `Subnet2Cidr`, `Subnet3Cidr`: change only if the defaults overlap with your network.
- `EC2InstanceType`: change if you need different sizing.
- `AmiId`: change only if you must use a region-specific or approved image.
- `InternalDomainName` and `AwideServerName`: change if your naming standard requires it.
- Awide Suite version is fixed in the template and not exposed as a launch parameter.

## Outputs to Record

After deployment, record these CloudFormation outputs:

- `EC2Hostname` for internal access
- `AwideSuiteEC2PrivateIP` for troubleshooting
- `EC2User` for host access
- `AwideSuitePassword` for first login; this value is the EC2 instance ID
- `S3LogsBucketName` for later analytics setup
- `FirehoseIAMRoleArn` for later Firehose configuration

## What Happens Next

After the stack is created:

1. Access the EC2 instance using your approved method, such as Session Manager.
2. Use `AwideSuitePassword` as the initial application password.
3. Verify that the private hostname resolves inside the VPC.
4. Continue with `configure.md` to connect the product to the target RDS instance and enable log delivery.

## Out of Scope for the Launch Template

The Marketplace deployment does not complete customer-specific integration work. You still need to configure:

- Connectivity from the EC2 instance to the target RDS PostgreSQL instance
- RDS log publishing to CloudWatch Logs
- Firehose delivery and subscription filters for extended analytics
- Any environment-specific security or routing changes

## Troubleshooting

If deployment fails, first check the CloudFormation event that failed, then confirm the AMI is valid in the selected region, the CIDR ranges do not overlap existing networks, the chosen instance type is available, and the account can create IAM and Route 53 resources.