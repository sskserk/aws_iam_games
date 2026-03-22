aws cloudformation create-stack --region eu-central-1 \
    --stack-name logging-tantor-stack23 --template-body file://firehose-s3.yaml  --capabilities CAPABILITY_IAM

