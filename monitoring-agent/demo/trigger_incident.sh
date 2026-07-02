#!/bin/bash
# Script to trigger incidents for testing

source ../config.sh
echo "Triggering failures..."
for i in {1..10}; do
  aws lambda invoke --function-name $FAULTY_FUNCTION /tmp/out.json > /dev/null
  sleep 2
done
aws cloudwatch describe-alarms --alarm-names $ALARM_NAME --query 'MetricAlarms[0].StateValue' --output text
aws logs tail /aws/lambda/$AGENT_FUNCTION --follow