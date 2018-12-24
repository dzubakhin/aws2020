#!/bin/sh

# Simple script for deploing all with nessessary paramerers

aws s3 cp ./app.pp s3://30daysdevops/nick/

# Create ELB Stack
aws --output text cloudformation create-stack \
    --template-body file://app_ELB.yml \
    --stack-name nick-app-ELB \
    --parameters ParameterKey=Environment,ParameterValue=qa

# Create connected ASG stack
aws --output text cloudformation create-stack \
    --template-body file://app_ASG.yml \
    --stack-name nick-app-ASG \
    --parameters ParameterKey=Environment,ParameterValue=qa \
                 ParameterKey=ELBStackName,ParameterValue=nick-app-ELB \
    --capabilities CAPABILITY_IAM
