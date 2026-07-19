# Lambda function for monitoring agent

import json
import boto3
import time
import urllib.request

logs_client = boto3.client('logs')
secrets_client = boto3.client('secretsmanager')

def get_secret(secret_name):
    response = secrets_client.get_secret_value(SecretId=secret_name)
    return response['SecretString']

def get_recent_logs(log_group_name, minutes=10):
    query = """
    fields @timestamp, @message
    | filter @message like /ERROR|Exception|Traceback/
    | sort @timestamp desc
    | limit 20
    """
    start_query = logs_client.start_query(
        logGroupName=log_group_name,
        startTime=int(time.time()) - (minutes * 60),
        endTime=int(time.time()),
        queryString=query
    )
    query_id = start_query['queryId']
    for _ in range(10):
        result = logs_client.get_query_results(queryId=query_id)
        if result['status'] == 'Complete':
            break
        time.sleep(1)
    log_lines = []
    for row in result.get('results', []):
        entry = {field['field']: field['value'] for field in row}
        log_lines.append(entry.get('@message', ''))
    return log_lines

def call_groq(prompt):
    api_key = get_secret('monitoring-agent/groq-key')
    url = "https://api.groq.com/openai/v1/chat/completions"
    payload = {
        "model": "llama-3.3-70b-versatile",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.3,
    }
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {api_key}',
            'User-Agent': 'Mozilla/5.0 (compatible; IncidentAgent/1.0)',
        },
        method='POST'
    )
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode('utf-8'))
    return result['choices'][0]['message']['content']

def post_to_slack(message):
    webhook_url = get_secret('monitoring-agent/slack-webhook')
    payload = {"text": message}
    req = urllib.request.Request(
        webhook_url, data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    urllib.request.urlopen(req)

def handler(event, context):
    detail = event.get('detail', {})
    alarm_name = detail.get('alarmName', 'Unknown alarm')
    log_group_name = "/aws/lambda/faulty-order-service"

    logs = get_recent_logs(log_group_name)
    logs_text = "\n".join(logs) if logs else "No recent error logs found."

    prompt = f"""
You are an SRE assistant. An alarm fired: "{alarm_name}".

Recent error logs from the affected service:
{logs_text}

Provide a concise incident summary with:
1. WHAT broke (one sentence)
2. LIKELY CAUSE (based on the logs)
3. CONFIDENCE (high/medium/low)
4. SEVERITY (low/medium/high)
Keep it under 100 words.
"""
    try:
        summary = call_groq(prompt)
    except Exception as e:
        summary = f"(Groq call failed: {str(e)}) Raw logs:\n{logs_text[:500]}"

    slack_message = f"🚨 *Incident Alert: {alarm_name}*\n\n{summary}"
    post_to_slack(slack_message)
    return {"statusCode": 200, "body": "Processed"}