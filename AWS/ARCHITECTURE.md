# AWS Infrastructure Architecture

## High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                                                                 │
│                            GitHub Repository                                     │
│                     (Actions Workflows & Source Code)                           │
│                                                                                 │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     │
                                     │ Webhook/Workflow Trigger
                                     │
                     ┌───────────────▼────────────────┐
                     │                                │
                     │    GitHub Actions Workflow     │
                     │    (Deploy/Destroy)            │
                     │                                │
                     └───────────────┬────────────────┘
                                     │
                                     │ AWS API Calls (Terraform)
                                     │
┌────────────────────────────────────▼─────────────────────────────────────────────┐
│                                                                                  │
│                              AWS Cloud (us-east-1)                               │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │                        S3 + DynamoDB                                      │  │
│  │                  (Terraform State Backend)                                │  │
│  │  ┌──────────────────────┐      ┌─────────────────────────────────┐      │  │
│  │  │ S3 Bucket            │      │ DynamoDB Table                  │      │  │
│  │  │ - Versioning         │      │ - State Locking                 │      │  │
│  │  │ - Encryption         │      │ - LockID (Hash Key)             │      │  │
│  │  │ - State Files        │      │                                 │      │  │
│  │  └──────────────────────┘      └─────────────────────────────────┘      │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │                   VPC (10.0.0.0/16) - us-east-1a                         │  │
│  │                                                                           │  │
│  │  ┌────────────────────────────────┐   ┌────────────────────────────────┐ │  │
│  │  │   Public Subnet (10.0.1.0/24)  │   │ Private Subnet (10.0.2.0/24)   │ │  │
│  │  │                                │   │                                │ │  │
│  │  │  ┌──────────────────────────┐  │   │  ┌──────────────────────────┐  │ │  │
│  │  │  │  NAT Gateway             │  │   │  │  EC2 Instance            │  │ │  │
│  │  │  │  (Elastic IP)            │◄─┼───┼──│  - t3.medium             │  │ │  │
│  │  │  │                          │  │   │  │  - Ubuntu 22.04          │  │ │  │
│  │  │  │  Routes traffic to IGW   │  │   │  │  - 50GB EBS (encrypted)  │  │ │  │
│  │  │  └──────────┬───────────────┘  │   │  │                          │  │ │  │
│  │  │             │                  │   │  │  Installed Software:     │  │ │  │
│  │  │  ┌──────────▼───────────────┐  │   │  │  ├─ Docker Engine       │  │ │  │
│  │  │  │  Internet Gateway        │  │   │  │  ├─ Docker Compose      │  │ │  │
│  │  │  │  (IGW)                   │  │   │  │  ├─ Nginx (port 80)     │  │ │  │
│  │  │  └──────────────────────────┘  │   │  │  ├─ GitHub Runner       │  │ │  │
│  │  │                                │   │  │  ├─ AWS CLI             │  │ │  │
│  │  │  Route Tables:                 │   │  │  ├─ Node.js             │  │ │  │
│  │  │  - Public: 0.0.0.0/0 → IGW    │   │  │  └─ Python              │  │ │  │
│  │  │                                │   │  │                          │  │ │  │
│  │  └────────────────────────────────┘   │  │  Security Group:         │  │ │  │
│  │                                        │  │  Ingress:                │  │ │  │
│  │  Route Tables:                         │  │  - 22 (SSH)              │  │ │  │
│  │  - Private: 0.0.0.0/0 → NAT GW        │  │  - 80 (HTTP)             │  │ │  │
│  │                                        │  │  - 443 (HTTPS)           │  │ │  │
│  │  VPC Endpoints:                        │  │  Egress:                 │  │ │  │
│  │  - S3 Gateway Endpoint                 │  │  - All (for GitHub)      │  │ │  │
│  │                                        │  │                          │  │ │  │
│  │                                        │  │  IAM Role:               │  │ │  │
│  │                                        │  │  - ECR access            │  │ │  │
│  │                                        │  │  - S3 access             │  │ │  │
│  │                                        │  │  - CloudWatch Logs       │  │ │  │
│  │                                        │  └──────────────────────────┘  │ │  │
│  │                                        │                                │ │  │
│  └────────────────────────────────────────┴────────────────────────────────┘ │  │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     │ HTTPS (443) - Egress Only
                                     │
                     ┌───────────────▼────────────────┐
                     │                                │
                     │        GitHub.com              │
                     │   (Runner Registration &       │
                     │    Workflow Execution)         │
                     │                                │
                     └────────────────────────────────┘
```

## Network Flow

### 1. Deployment Flow

```
Developer → GitHub → Workflow → Terraform → AWS API
                                              ↓
                                    ┌─────────────────┐
                                    │  Infrastructure │
                                    │  Created:       │
                                    │  - VPC          │
                                    │  - Subnets      │
                                    │  - NAT Gateway  │
                                    │  - EC2          │
                                    └─────────────────┘
```

### 2. GitHub Runner Communication

```
┌──────────────┐           ┌────────────┐           ┌─────────────┐
│              │           │            │           │             │
│  EC2 Runner  │──Egress──▶│ NAT Gateway│──────────▶│ GitHub.com  │
│  (Private)   │           │ (Public)   │           │             │
│              │           │            │           │             │
└──────────────┘           └────────────┘           └─────────────┘
   Private IP              Elastic IP               Internet
   10.0.2.x                Public IP                443/HTTPS
```

### 3. Docker Container Flow

```
┌────────────────────────────────────────────────┐
│            EC2 Instance                        │
│                                                │
│  ┌──────────────────────────────────────────┐ │
│  │  Nginx (Port 80)                         │ │
│  │  └─Proxy─▶ Docker Container (Port 8080)  │ │
│  └──────────────────────────────────────────┘ │
│                                                │
│  ┌──────────────────────────────────────────┐ │
│  │  GitHub Runner                           │ │
│  │  - Polls GitHub for jobs                 │ │
│  │  - Executes workflows                    │ │
│  │  - Uses Docker for builds                │ │
│  └──────────────────────────────────────────┘ │
└────────────────────────────────────────────────┘
```

## Component Details

### VPC Configuration

| Component | Configuration |
|-----------|--------------|
| **VPC CIDR** | 10.0.0.0/16 (65,536 IPs) |
| **Public Subnet** | 10.0.1.0/24 (256 IPs) |
| **Private Subnet** | 10.0.2.0/24 (256 IPs) |
| **Availability Zone** | us-east-1a (configurable) |
| **DNS Hostnames** | Enabled |
| **DNS Resolution** | Enabled |

### Routing Configuration

#### Public Route Table
```
Destination     Target
0.0.0.0/0       igw-xxxxx (Internet Gateway)
10.0.0.0/16     local
```

#### Private Route Table
```
Destination     Target
0.0.0.0/0       nat-xxxxx (NAT Gateway)
10.0.0.0/16     local
```

### Security Groups

#### EC2 Security Group

**Ingress Rules:**
```
Port    Protocol    Source          Description
22      TCP         YOUR_IP/32      SSH access
80      TCP         0.0.0.0/0       HTTP for Nginx
443     TCP         0.0.0.0/0       HTTPS for Nginx
```

**Egress Rules:**
```
Port    Protocol    Destination     Description
All     All         0.0.0.0/0       Allow all outbound (GitHub, packages)
443     TCP         0.0.0.0/0       HTTPS (GitHub API)
80      TCP         0.0.0.0/0       HTTP (package downloads)
53      TCP/UDP     0.0.0.0/0       DNS resolution
```

### IAM Permissions

#### EC2 Instance Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "*"
    }
  ]
}
```

## Data Flow Diagrams

### Terraform State Management

```
┌─────────────────┐
│  Terraform CLI  │
│  (Local/GitHub) │
└────────┬────────┘
         │
         │ 1. Lock state
         ▼
┌─────────────────┐
│   DynamoDB      │
│   Lock Table    │
└────────┬────────┘
         │
         │ 2. Read/Write state
         ▼
┌─────────────────┐
│   S3 Bucket     │
│   State File    │
└────────┬────────┘
         │
         │ 3. Unlock
         ▼
┌─────────────────┐
│   DynamoDB      │
│   Lock Released │
└─────────────────┘
```

### GitHub Runner Workflow Execution

```
1. GitHub Webhook
        ↓
2. Runner polls GitHub
        ↓
3. Job assigned to runner
        ↓
4. Runner fetches code
        ↓
5. Docker containers created
        ↓
6. Workflow steps executed
        ↓
7. Artifacts uploaded
        ↓
8. Results sent to GitHub
        ↓
9. Runner waits for next job
```

## Scalability Considerations

### Horizontal Scaling

To add more runners:

```hcl
# In terraform.tfvars
runner_count = 3  # Multiple EC2 instances

# Each gets:
# - Unique runner name (runner-01, runner-02, etc.)
# - Same VPC and subnet
# - Load balanced by GitHub
```

### Vertical Scaling

Adjust instance size:

```hcl
instance_type = "t3.large"   # 2 vCPU, 8GB RAM
instance_type = "t3.xlarge"  # 4 vCPU, 16GB RAM
instance_type = "t3.2xlarge" # 8 vCPU, 32GB RAM
```

### Storage Scaling

Increase EBS volume:

```hcl
root_block_device {
  volume_size = 100  # GB
  volume_type = "gp3"
  iops        = 3000
  throughput  = 125  # MB/s
}
```

## High Availability Options

### Multi-AZ Deployment

```hcl
# Modify networking module
availability_zones = ["us-east-1a", "us-east-1b"]

# Creates:
# - 2 public subnets (one per AZ)
# - 2 private subnets (one per AZ)
# - 2 NAT Gateways (one per AZ)
# - Auto Scaling Group for runners
```

### Auto Scaling

```hcl
# Add auto scaling group
resource "aws_autoscaling_group" "runner" {
  min_size         = 1
  max_size         = 5
  desired_capacity = 2
  
  # Scale based on:
  # - CPU utilization
  # - GitHub queue depth
  # - Time of day
}
```

## Disaster Recovery

### State File Backup

```bash
# S3 versioning enabled
# To restore previous state:
aws s3api list-object-versions \
  --bucket testcontainers-terraform-state \
  --prefix aws/ec2-runner/

# Download specific version
aws s3api get-object \
  --bucket testcontainers-terraform-state \
  --key aws/ec2-runner/terraform.tfstate \
  --version-id VERSION_ID \
  terraform.tfstate.backup
```

### Infrastructure Rebuild

```bash
# Complete rebuild from scratch
terraform destroy
terraform apply

# Runner auto-registers on boot
# State preserved in S3
```

## Monitoring & Observability

### CloudWatch Dashboards

```
Metrics to Monitor:
- EC2 CPU Utilization
- NAT Gateway Bytes In/Out
- EBS Read/Write Operations
- Network In/Out
- Runner Job Queue Length
```

### Logging

```
Log Sources:
- /var/log/user-data.log      (Instance setup)
- /var/log/syslog              (System logs)
- ~/actions-runner/_diag/      (Runner logs)
- /var/log/nginx/access.log    (Nginx access)
- /var/log/nginx/error.log     (Nginx errors)
```

## Security Architecture

### Defense in Depth

```
Layer 1: Network
  ├─ Private subnet (no direct internet)
  ├─ Security groups (least privilege)
  └─ NAT Gateway (egress only)

Layer 2: Instance
  ├─ IMDSv2 required (metadata security)
  ├─ Encrypted EBS volumes
  └─ Minimal software installation

Layer 3: Application
  ├─ IAM roles (no static credentials)
  ├─ Runner isolation
  └─ Docker security

Layer 4: Data
  ├─ Encrypted S3 state
  ├─ Versioned state files
  └─ State locking
```

---

For implementation details, see [README.md](./README.md)
