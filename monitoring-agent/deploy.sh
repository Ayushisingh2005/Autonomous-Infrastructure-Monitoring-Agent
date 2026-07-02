#!/bin/bash
# Deployment script for monitoring agent

set -e
source config.sh

echo "== Creating IAM roles =="
aws iam create-role --role-name lambda-basic-execution \
  --assume-role-policy-document file://iam/lambda-trust-policy.json || true
aws iam attach-role-policy --role-name lambda-basic-execution \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam create-role --role-name incident-agent-role \
  --assume-role-policy-document file://iam/lambda-trust-policy.json || true
aws iam attach-role-policy --role-name incident-agent-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam put-role-policy --role-name incident-agent-role \
  --policy-name agent-permissions --policy-document file://iam/agent-permissions-policy.json

echo "Waiting for IAM propagation..."
sleep 10

echo "== Deploying faulty service =="
cd faulty-service && zip -q function.zip index.py && cd ..
aws lambda create-function --function-name $FAULTY_FUNCTION \
  --runtime python3.12 --role arn:aws:iam::$AWS_ACCOUNT_ID:role/lambda-basic-execution \
  --handler index.handler --zip-file fileb://faulty-service/function.zip

echo "== Deploying agent Lambda =="
cd agent-lambda && zip -q function.zip index.py && cd ..
aws lambda create-function --function-name $AGENT_FUNCTION \
  --runtime python3.12 --role arn:aws:iam::$AWS_ACCOUNT_ID:role/incident-agent-role \
  --handler index.handler --timeout 30 --zip-file fileb://agent-lambda/function.zip

echo "== Creating CloudWatch alarm =="
aws cloudwatch put-metric-alarm --alarm-name $ALARM_NAME \
  --namespace AWS/Lambda --metric-name Errors \
  --dimensions Name=FunctionName,Value=$FAULTY_FUNCTION \
  --statistic Sum --period 60 --evaluation-periods 1 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching

echo "== Wiring EventBridge =="
aws events put-rule --name $EVENT_RULE \
  --event-pattern '{"source":["aws.cloudwatch"],"detail-type":["CloudWatch Alarm State Change"],"detail":{"state":{"value":["ALARM"]}}}'

aws lambda add-permission --function-name $AGENT_FUNCTION \
  --statement-id eventbridge-invoke --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/$EVENT_RULE || true

aws events put-targets --rule $EVENT_RULE \
  --targets "Id=1,Arn=arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$AGENT_FUNCTION"

echo "✅ Done. Create secrets manually, then run demo/trigger_incident.sh"