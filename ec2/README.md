# 0. About

A Cloud Formation stack that does:
- Creates 1x instances of EC2, RDS Postgres, IAM Role + attached inline policy.
- Attaches created IAM Role to the EC2 and thus allows it to query the RDS Instance host metrics. 

# 1. Edit CloudFormation stack
## Specify SSH key name
Edit the ec2_cwatch.yaml, change the name of the key into required

```yaml
  KeyName:
    Type: AWS::EC2::KeyPair::KeyName
    Description: EC2 KeyPair for SSH access
    Default: trantor_key
```

# 2. Create CloudFormation stack
```bash
aws cloudformation create-stack --region eu-central-1 --stack-name ec2-tantor-stack --template-body file://ec2_cwatch.yaml  --capabilities CAPABILITY_IAM
```
Note: if necessary mention a different stack name


# 3. Wait until the stack is created
....wait


# 4. Login EC2

Access EC2 via SSH using specified key

# 5. Request CloudWatch metrics from within the EC2

Query a metric (e.g. CPUUtilization)
```bash
aws cloudwatch get-metric-statistics   --namespace AWS/RDS   --metric-name CPUUtilization   --dimensions Name=DBInstanceIdentifier,Value=ec2-tantor-stack-pg   --start-time 2025-08-27T18:00:00Z   --end-time 2025-08-27T22:00:00Z   --period 300   --statistics Average --region=eu-central-1
```
Note: specify correct time range (start-time & end-time)

## N. Delete stack (optional)

```bash
aws cloudformation delete-stack --region eu-central-1  --stack-name  ec2-tantor-stack
```