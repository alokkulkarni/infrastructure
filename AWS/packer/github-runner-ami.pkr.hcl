packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "ami_name_prefix" {
  type    = string
  default = "github-runner-ubuntu-22.04"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  ami_name  = "${var.ami_name_prefix}-${local.timestamp}"
}

source "amazon-ebs" "ubuntu" {
  ami_name      = local.ami_name
  instance_type = var.instance_type
  region        = var.region
  
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }
  
  ssh_username = var.ssh_username
  
  # Use temporary security group and subnet
  temporary_security_group_source_public_ip = true
  
  # Increased timeout for AMI creation
  aws_polling {
    delay_seconds = 15
    max_attempts  = 360
  }
  
  # Tags for the AMI
  tags = {
    Name          = "${var.ami_name_prefix}-${local.timestamp}"
    Base_AMI_Name = "{{ .SourceAMIName }}"
    Created       = "${local.timestamp}"
    BuildTool     = "Packer"
    Purpose       = "GitHub Actions Self-Hosted Runner"
    OS            = "Ubuntu 22.04"
  }
  
  # Tags for the snapshot
  snapshot_tags = {
    Name      = "${var.ami_name_prefix}-${local.timestamp}-snapshot"
    BuildTool = "Packer"
  }
  
  # EBS settings
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
  }
}

build {
  name = "github-runner-ami"
  
  sources = [
    "source.amazon-ebs.ubuntu"
  ]
  
  # Wait for cloud-init to finish
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo 'Cloud-init completed.'"
    ]
  }
  
  # Disable IPv6 permanently
  provisioner "shell" {
    inline = [
      "echo 'Disabling IPv6 permanently...'",
      "sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1",
      "sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1",
      "echo 'net.ipv6.conf.all.disable_ipv6=1' | sudo tee -a /etc/sysctl.conf",
      "echo 'net.ipv6.conf.default.disable_ipv6=1' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl -p"
    ]
  }
  
  # Configure apt with multiple mirrors and IPv4-only
  provisioner "shell" {
    inline = [
      "echo 'Configuring apt with multiple mirrors...'",
      "sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup",
      "sudo tee /etc/apt/sources.list > /dev/null <<'EOF'",
      "# Primary: AWS EC2 regional mirror (fastest for EC2 instances)",
      "deb http://eu-west-2.ec2.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse",
      "deb http://eu-west-2.ec2.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse",
      "deb http://eu-west-2.ec2.archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse",
      "",
      "# Fallback 1: Main Ubuntu archive",
      "deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse",
      "deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse",
      "deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse",
      "EOF",
      "",
      "# Configure apt for IPv4-only with timeouts",
      "sudo tee /etc/apt/apt.conf.d/99custom-settings > /dev/null <<'EOF'",
      "Acquire::ForceIPv4 \"true\";",
      "Acquire::http::Timeout \"30\";",
      "Acquire::https::Timeout \"30\";",
      "Acquire::Retries \"3\";",
      "EOF"
    ]
  }
  
  # Update system
  provisioner "shell" {
    inline = [
      "echo 'Updating system packages...'",
      "sudo apt-get update",
      "sudo apt-get upgrade -y"
    ]
  }
  
  # Install essential packages
  provisioner "shell" {
    inline = [
      "echo 'Installing essential packages...'",
      "sudo apt-get install -y curl wget git unzip jq ca-certificates gnupg lsb-release software-properties-common build-essential"
    ]
  }
  
  # Install Docker
  provisioner "shell" {
    inline = [
      "echo 'Installing Docker...'",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "docker --version",
      "docker compose version"
    ]
  }
  
  # Install Nginx
  provisioner "shell" {
    inline = [
      "echo 'Installing Nginx...'",
      "sudo apt-get install -y nginx",
      "sudo systemctl enable nginx",
      "sudo nginx -v"
    ]
  }
  
  # Install AWS CLI
  provisioner "shell" {
    inline = [
      "echo 'Installing AWS CLI...'",
      "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "rm -rf aws awscliv2.zip",
      "aws --version"
    ]
  }
  
  # Install Node.js 20.x
  provisioner "shell" {
    inline = [
      "echo 'Installing Node.js...'",
      "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -",
      "sudo apt-get install -y nodejs",
      "node --version",
      "npm --version"
    ]
  }
  
  # Install Python and pip
  provisioner "shell" {
    inline = [
      "echo 'Installing Python...'",
      "sudo apt-get install -y python3 python3-pip python3-venv",
      "python3 --version",
      "pip3 --version"
    ]
  }
  
  # Pre-create runner user and directory structure
  provisioner "shell" {
    inline = [
      "echo 'Creating runner user and directory structure...'",
      "sudo useradd -m -s /bin/bash runner",
      "sudo usermod -aG docker runner",
      "sudo mkdir -p /home/runner/actions-runner",
      "sudo chown -R runner:runner /home/runner"
    ]
  }
  
  # Pre-download GitHub Actions Runner (latest version)
  provisioner "shell" {
    inline = [
      "echo 'Pre-downloading GitHub Actions Runner...'",
      "RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')",
      "echo \"Runner version: $RUNNER_VERSION\"",
      "cd /home/runner/actions-runner",
      "sudo -u runner curl -o actions-runner-linux-x64-$RUNNER_VERSION.tar.gz -L https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz",
      "sudo -u runner tar xzf actions-runner-linux-x64-$RUNNER_VERSION.tar.gz",
      "sudo -u runner rm actions-runner-linux-x64-$RUNNER_VERSION.tar.gz",
      "ls -la /home/runner/actions-runner/"
    ]
  }
  
  # Install runner dependencies
  provisioner "shell" {
    inline = [
      "echo 'Installing runner dependencies...'",
      "cd /home/runner/actions-runner",
      "sudo ./bin/installdependencies.sh"
    ]
  }
  
  # Create log directory
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /var/log/github-runner",
      "sudo chown runner:runner /var/log/github-runner"
    ]
  }
  
  # Clean up
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up...'",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",
      
      # Clear bash history
      "cat /dev/null > ~/.bash_history && history -c"
    ]
  }
  
  # Display installed versions
  provisioner "shell" {
    inline = [
      "echo '=========================================='",
      "echo 'AMI Build Summary'",
      "echo '=========================================='",
      "echo 'Docker version:' $(docker --version)",
      "echo 'Docker Compose version:' $(docker compose version)",
      "echo 'Nginx version:' $(sudo nginx -v 2>&1)",
      "echo 'AWS CLI version:' $(aws --version)",
      "echo 'Node.js version:' $(node --version)",
      "echo 'npm version:' $(npm --version)",
      "echo 'Python version:' $(python3 --version)",
      "echo 'pip version:' $(pip3 --version)",
      "echo 'Git version:' $(git --version)",
      "echo 'Runner user exists:' $(id runner &>/dev/null && echo 'YES' || echo 'NO')",
      "echo 'Runner directory:' $(ls -ld /home/runner/actions-runner 2>/dev/null || echo 'NOT FOUND')",
      "echo '=========================================='",
      "echo 'Build completed at:' $(date)",
      "echo '=========================================='",
    ]
  }
  
  # Create manifest file
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
    custom_data = {
      ami_region    = var.region
      ami_name      = local.ami_name
      instance_type = var.instance_type
      build_time    = local.timestamp
    }
  }
}
