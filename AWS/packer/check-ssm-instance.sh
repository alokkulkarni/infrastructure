#!/bin/bash
# Check if a specific EC2 instance is registered with SSM

if [ -z "$1" ]; then
    echo "Usage: $0 <instance-id> [region]"
    echo "Example: $0 i-04c2f1274a7d4c150 eu-west-2"
    exit 1
fi

INSTANCE_ID="$1"
REGION="${2:-eu-west-2}"

echo "Checking SSM connectivity for instance: $INSTANCE_ID"
echo "Region: $REGION"
echo ""

# Check if instance is running
echo "1. Checking instance state..."
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null)

if [ "$INSTANCE_STATE" = "running" ]; then
    echo "   ✓ Instance is running"
else
    echo "   ✗ Instance state: $INSTANCE_STATE"
    exit 1
fi
echo ""

# Check if instance has IAM role
echo "2. Checking IAM instance profile..."
INSTANCE_PROFILE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text 2>/dev/null)

if [ -n "$INSTANCE_PROFILE" ] && [ "$INSTANCE_PROFILE" != "None" ]; then
    echo "   ✓ Instance profile attached: $INSTANCE_PROFILE"
else
    echo "   ✗ No instance profile attached"
    exit 1
fi
echo ""

# Check if instance has public IP
echo "3. Checking network configuration..."
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null)

PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text 2>/dev/null)

if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ]; then
    echo "   ✓ Public IP: $PUBLIC_IP"
else
    echo "   ⚠ No public IP (instance might be in private subnet)"
fi
echo "   Private IP: $PRIVATE_IP"
echo ""

# Check if registered with SSM
echo "4. Checking SSM registration..."
SSM_STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --region "$REGION" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null)

if [ "$SSM_STATUS" = "Online" ]; then
    echo "   ✓ Instance is registered with SSM and online"
    
    # Get more details
    aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --region "$REGION" \
        --query 'InstanceInformationList[0]' \
        --output json | jq '{PingStatus, LastPingDateTime, PlatformType, PlatformName, PlatformVersion, AgentVersion}'
    
    echo ""
    echo "✓ You should be able to connect via SSM now"
    echo ""
    echo "Test connection with:"
    echo "  aws ssm start-session --target $INSTANCE_ID --region $REGION"
    
elif [ "$SSM_STATUS" = "ConnectionLost" ]; then
    echo "   ⚠ Instance was registered but connection lost"
    echo "   This usually means the SSM agent stopped or network connectivity issues"
else
    echo "   ✗ Instance not registered with SSM"
    echo ""
    echo "Possible reasons:"
    echo "  1. SSM agent not running on the instance"
    echo "  2. Instance can't reach SSM endpoints (no internet access)"
    echo "  3. IAM instance profile missing SSM permissions"
    echo "  4. SSM agent still starting up (wait 2-3 minutes after instance launch)"
    echo ""
    echo "To debug, check instance console output:"
    echo "  aws ec2 get-console-output --instance-id $INSTANCE_ID --region $REGION --output text"
fi
echo ""

# Check security group rules
echo "5. Checking security groups..."
SECURITY_GROUPS=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
    --output text 2>/dev/null)

echo "   Security Groups: $SECURITY_GROUPS"
echo "   Note: SSM doesn't require any inbound rules, only outbound HTTPS (443) access"
echo ""

# Check VPC and subnet
echo "6. Checking VPC configuration..."
SUBNET_ID=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].SubnetId' \
    --output text 2>/dev/null)

VPC_ID=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].VpcId' \
    --output text 2>/dev/null)

echo "   VPC ID: $VPC_ID"
echo "   Subnet ID: $SUBNET_ID"

# Check if subnet has route to internet
ROUTE_TABLE=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
    --region "$REGION" \
    --query 'RouteTables[0].RouteTableId' \
    --output text 2>/dev/null)

if [ -z "$ROUTE_TABLE" ] || [ "$ROUTE_TABLE" = "None" ]; then
    ROUTE_TABLE=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
        --region "$REGION" \
        --query 'RouteTables[0].RouteTableId' \
        --output text 2>/dev/null)
    echo "   Using main route table: $ROUTE_TABLE"
else
    echo "   Route table: $ROUTE_TABLE"
fi

IGW=$(aws ec2 describe-route-tables \
    --route-table-ids "$ROUTE_TABLE" \
    --region "$REGION" \
    --query 'RouteTables[0].Routes[?GatewayId!=`local`].GatewayId' \
    --output text 2>/dev/null)

if [[ "$IGW" == igw-* ]]; then
    echo "   ✓ Has route to Internet Gateway: $IGW"
elif [[ "$IGW" == nat-* ]]; then
    echo "   ✓ Has route to NAT Gateway: $IGW"
else
    echo "   ✗ No route to internet (this will prevent SSM connectivity)"
fi
