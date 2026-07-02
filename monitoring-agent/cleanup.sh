#!/bin/bash
# Cleanup script for monitoring agent

source config.sh
aws lambda delete-function --function-name $FAULTY_FUNCTION
aws lambda delete-function --function-name $AGENT_FUNCTION
aws cloudwatch delete-alarms --alarm-names $ALARM_NAME
aws events remove-targets --rule $EVENT_RULE --ids "1"
aws events delete-rule --name $EVENT_RULE