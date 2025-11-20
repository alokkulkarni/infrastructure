#!/bin/bash
set -e

INSTANCE_ID="i-0e687c0770fbe76f6"
BASTION_IP="13.134.57.181"
PRIVATE_IP="10.0.2.225"

echo "=========================================="
echo "Deploying Runner Fix to EC2 Instance"
echo "=========================================="
echo "Instance: $INSTANCE_ID"
echo "Private IP: $PRIVATE_IP"
echo ""

# Generate a new runner token
echo "🔐 Generating fresh GitHub runner token..."
RUNNER_TOKEN=$(gh api -X POST repos/alokkulkarni/sit-test-repo/actions/runners/registration-token --jq .token)

if [ -z "$RUNNER_TOKEN" ]; then
    echo "❌ Failed to generate runner token"
    exit 1
fi

echo "✅ Token generated (length: ${#RUNNER_TOKEN} characters)"
echo ""

# Copy the fix script to bastion
echo "📤 Copying fix script to bastion host..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    /tmp/fix-runner-on-ec2.sh ubuntu@$BASTION_IP:/tmp/

# Copy from bastion to private instance
echo "📤 Copying fix script to private instance..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ubuntu@$BASTION_IP \
    "scp -o StrictHostKeyChecking=no /tmp/fix-runner-on-ec2.sh ubuntu@$PRIVATE_IP:/tmp/"

# Execute the fix script
echo "🚀 Executing fix script on instance..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -J ubuntu@$BASTION_IP \
    ubuntu@$PRIVATE_IP \
    "sudo bash /tmp/fix-runner-on-ec2.sh \
        'https://github.com/alokkulkarni/sit-test-repo' \
        '$RUNNER_TOKEN' \
        'aws-ec2-runner-SIT-Alok-TeamA-20251120-1751' \
        'self-hosted,aws,linux,docker,dev,SIT-Alok-TeamA-20251120-1751'"

echo ""
echo "=========================================="
echo "✅ Fix deployment complete!"
echo "=========================================="
echo ""
echo "Verifying runner registration..."
sleep 5
gh api repos/alokkulkarni/sit-test-repo/actions/runners --jq '.runners[] | {name: .name, status: .status, labels: [.labels[].name]}'
