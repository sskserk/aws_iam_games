# Golden Image Stack

## What it is

This stack deploys one EC2 instance. It is used to build a "golden image".


## Making the golden image

1. Connect to the EC2 instance over SSH.
2. Check that Docker, Docker Compose, and the app are installed and working.
3. Do any extra setup you need.
4. Stop the instance.
5. Create an AMI from the instance. In the AWS Console: EC2 > Instances > select the instance > Actions > Image and templates > Create image.
6. This new AMI is your golden image. Use it to launch new instances.
