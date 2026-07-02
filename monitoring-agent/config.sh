#!/bin/bash
# Configuration file for monitoring agent
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-east-1"
export FAULTY_FUNCTION="faulty-order-service"
export AGENT_FUNCTION="incident-agent"
export ALARM_NAME="faulty-order-service-errors"
export EVENT_RULE="trigger-incident-agent"