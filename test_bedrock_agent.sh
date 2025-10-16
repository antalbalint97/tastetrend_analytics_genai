#!/usr/bin/env bash
region="eu-central-1"
agent_id="I85C7USBK6"
alias_id="6EUR1ENEUQ"
input_text="Hello, can you confirm you're responding from TasteTrend?"

/c/Users/Bálint/AppData/Local/Programs/Python/Python311/python.exe - <<EOF
import boto3, json

client = boto3.client('bedrock-agent-runtime', region_name='$region')

response = client.invoke_agent(
    agentId='$agent_id',
    agentAliasId='$alias_id',
    sessionId='test-session',
    inputText="""$input_text"""
)

for event in response['completion']:
    if 'chunk' in event:
        print(event['chunk']['bytes'].decode(), end='')
EOF
