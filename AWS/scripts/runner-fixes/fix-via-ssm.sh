#!/bin/bash
set -e

INSTANCE_ID="i-0e687c0770fbe76f6"

echo "=========================================="
echo "Attempting to fix runner via SSM"
echo "=========================================="

# Generate fresh token
echo "🔐 Generating fresh GitHub runner token..."
RUNNER_TOKEN=$(gh api -X POST repos/alokkulkarni/sit-test-repo/actions/runners/registration-token --jq .token)

if [ -z "$RUNNER_TOKEN" ]; then
    echo "❌ Failed to generate runner token"
    exit 1
fi

echo "✅ Token generated (length: ${#RUNNER_TOKEN} characters)"
echo ""

# Read the fix script
FIX_SCRIPT=$(cat /tmp/fix-runner-on-ec2.sh)

# Send command via SSM
echo "🚀 Sending command to instance via SSM..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$FIX_SCRIPT\",\"exit 0\"]" \
    --comment "Fix GitHub Actions Runner" \
    --output text \
    --query 'Command.CommandId')

if [ -z "$COMMAND_ID" ]; then
    echo "❌ Failed to send SSM command"
    echo "SSM agent may not be installed or instance not registered"
    exit 1
fi

echo "✅ Command sent: $COMMAND_ID"
echo "⏳ Waiting for command to complete..."

# Wait and get results
sleep 10
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query '[Status,StandardOutputContent,StandardErrorContent]' \
    --output text

echo ""
echo "Verifying runner registration..."
gh api repos/alokkulkarni/sit-test-repo/actions/runners --jq '.runners[] | {name: .name, status: .status}'
