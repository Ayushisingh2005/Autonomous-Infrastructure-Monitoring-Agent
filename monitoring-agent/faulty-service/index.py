# Faulty service for testing monitoring agent

import random, json

def handler(event, context):
    if random.random() < 0.3:
        raise Exception("Simulated database connection timeout")
    return {"statusCode": 200, "body": json.dumps({"message": "Order processed successfully"})}