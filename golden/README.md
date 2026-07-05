aws --profile awmp s3 rm s3://awide-pg-suite-common --recursive

aws --profile awmp s3 cp ./suite_deploy/s3 s3://awide-pg-suite-common/common  --recursive --exclude ".DS_Store" 





aws --profile awide cloudformation create-stack --stack-name staging-golden-1 --template-body file://stack.yaml --capabilities CAPABILITY_IAM

 aws --profile awide ssm start-session --target i-09744c6d0a5a39615


 aws --profile awmp iam list-instance-profiles-for-role --role-name
 aws --profile awmp iam remove-role-from-instance-profile --instance-profile-name --role-name
  aws --profile awmp iam delete-role --role-name 