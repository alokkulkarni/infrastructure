#!/bin/bash
set -e

# ============================================================================
# GitHub Actions Runner - Manual Registration Test Script
# ============================================================================
# This script tests runner registration on an EC2 instance to verify the
# runner version and API endpoints are correct before creating an AMI.
#
# Usage:
#   1. SSH or SSM into your test instance
#   2. Copy this script to the instance
#   3. Run: sudo bash test-runner-registration.sh
#
# What it does:
#   - Checks if runner is already installed
#   - If not, downloads and installs latest runner version
#   - Verifies runner version
#   - Generates a fresh registration token
#   - Attempts registration with verbose logging
#   - Shows detailed error information if registration fails
# ============================================================================

GITHUB_REPO="alokkulkarni/sit-test-repo"
RUNNER_USER="runner"
RUNNER_DIR="/home/runner/actions-runner"
TEST_RUNNER_NAME="test-runner-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root (use sudo)"
    exit 1
fi

log "=========================================="
log "GitHub Actions Runner Registration Test"
log "=========================================="
log "Target Repository: $GITHUB_REPO"
log "Runner Name: $TEST_RUNNER_NAME"
log ""

# Check and install required packages
log "Checking required packages..."
REQUIRED_PACKAGES=("curl" "jq" "tar")
MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! command -v "$pkg" &> /dev/null; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    log "Installing missing packages: ${MISSING_PACKAGES[*]}"
    sudo apt update -qq
    sudo apt install -y "${MISSING_PACKAGES[@]}" -qq
    success "Required packages installed"
else
    success "All required packages present"
fi
log ""

# Step 1: Check if runner user exists
log "Step 1: Checking runner user..."
if id "$RUNNER_USER" &>/dev/null; then
    success "Runner user '$RUNNER_USER' exists"
else
    warning "Runner user '$RUNNER_USER' not found, creating..."
    useradd -m -s /bin/bash "$RUNNER_USER"
    success "Runner user created"
fi

# Step 2: Check if runner is already installed
log ""
log "Step 2: Checking runner installation..."
if [ -d "$RUNNER_DIR" ]; then
    if [ -f "$RUNNER_DIR/config.sh" ]; then
        success "Runner directory exists at $RUNNER_DIR"
        
        # Check version
        log "Checking runner version..."
        VERSION_OUTPUT=$(sudo -u "$RUNNER_USER" "$RUNNER_DIR/config.sh" --version 2>&1)
        CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP '(?<=Actions Runner Version: )\d+\.\d+\.\d+' || echo "unknown")
        
        if [ "$CURRENT_VERSION" != "unknown" ]; then
            log "Current runner version: $CURRENT_VERSION"
            
            # Check if version is recent enough (>= 2.310.0)
            REQUIRED_VERSION="2.310.0"
            if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$CURRENT_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
                success "Runner version $CURRENT_VERSION is compatible (>= 2.310.0)"
            else
                error "Runner version $CURRENT_VERSION is TOO OLD (< 2.310.0)"
                error "This version uses deprecated API endpoints"
                warning "You should reinstall with latest version"
                
                read -p "Do you want to reinstall the runner now? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    log "Backing up old runner directory..."
                    mv "$RUNNER_DIR" "${RUNNER_DIR}.old.$(date +%s)"
                    REINSTALL=true
                else
                    error "Cannot proceed with old runner version"
                    exit 1
                fi
            fi
        else
            error "Could not determine runner version from config.sh"
            log "Version check output was:"
            echo "$VERSION_OUTPUT"
            log ""
            warning "This likely means the runner installation is incomplete or corrupted"
            
            read -p "Do you want to reinstall the runner now? (Y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                log "Backing up old runner directory..."
                mv "$RUNNER_DIR" "${RUNNER_DIR}.old.$(date +%s)"
                REINSTALL=true
            else
                error "Cannot proceed without valid runner installation"
                exit 1
            fi
        fi
    else
        warning "Runner directory exists but config.sh not found"
        REINSTALL=true
    fi
else
    warning "Runner not installed"
    REINSTALL=true
fi

# Step 3: Install runner if needed
if [ "${REINSTALL}" = "true" ]; then
    log ""
    log "Step 3: Installing latest GitHub Actions runner..."
    
    # Get latest version from GitHub
    log "Fetching latest runner version from GitHub..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
    
    if [ -z "$LATEST_VERSION" ]; then
        error "Failed to fetch latest runner version"
        exit 1
    fi
    
    log "Latest runner version: $LATEST_VERSION"
    
    # Create runner directory with sudo, then set ownership
    log "Creating runner directory..."
    sudo mkdir -p "$RUNNER_DIR"
    sudo chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
    cd "$RUNNER_DIR"
    
    # Download runner
    log "Downloading runner v${LATEST_VERSION}..."
    DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${LATEST_VERSION}/actions-runner-linux-x64-${LATEST_VERSION}.tar.gz"
    
    sudo -u "$RUNNER_USER" curl -o "actions-runner-linux-x64-${LATEST_VERSION}.tar.gz" -L "$DOWNLOAD_URL"
    
    if [ $? -ne 0 ]; then
        error "Failed to download runner"
        exit 1
    fi
    
    success "Runner downloaded"
    
    # Extract runner
    log "Extracting runner..."
    sudo -u "$RUNNER_USER" tar xzf "actions-runner-linux-x64-${LATEST_VERSION}.tar.gz"
    sudo -u "$RUNNER_USER" rm "actions-runner-linux-x64-${LATEST_VERSION}.tar.gz"
    
    success "Runner extracted"
    
    # Verify installation
    log "Verifying installation..."
    VERSION_OUTPUT=$(sudo -u "$RUNNER_USER" "$RUNNER_DIR/config.sh" --version 2>&1)
    log "Version command output:"
    echo "$VERSION_OUTPUT"
    
    INSTALLED_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP '(?<=Actions Runner Version: )\d+\.\d+\.\d+' || echo "unknown")
    
    if [ "$INSTALLED_VERSION" = "unknown" ]; then
        warning "Could not parse version from output, but runner appears to be installed"
        log "Checking if config.sh is executable and present..."
        if [ -x "$RUNNER_DIR/config.sh" ]; then
            success "config.sh is present and executable"
            warning "Proceeding with registration (version detection failed but runner seems OK)"
            INSTALLED_VERSION="$LATEST_VERSION"
        else
            error "config.sh not found or not executable"
            exit 1
        fi
    elif [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        success "Runner v${INSTALLED_VERSION} installed successfully"
    else
        warning "Version mismatch: installed $INSTALLED_VERSION, expected $LATEST_VERSION"
        warning "Proceeding anyway as runner is installed"
    fi
fi

# Step 4: Generate registration token
log ""
log "Step 4: Generating registration token..."
log ""

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    log "GitHub CLI (gh) is not installed. Installing..."
    
    # Install GitHub CLI
    sudo mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update -qq
    sudo apt install -y gh -qq
    
    if ! command -v gh &> /dev/null; then
        error "Failed to install GitHub CLI"
        echo ""
        warning "Alternative: Generate token manually at:"
        warning "https://github.com/$GITHUB_REPO/settings/actions/runners/new"
        echo ""
        read -p "Enter registration token manually: " REGISTRATION_TOKEN
    else
        success "GitHub CLI installed successfully"
    fi
fi

# Authenticate with GitHub if not already authenticated
if command -v gh &> /dev/null; then
    if ! gh auth status &> /dev/null; then
        log "GitHub CLI not authenticated"
        echo ""
        warning "You need to authenticate GitHub CLI"
        warning "Options:"
        warning "1. Use PAT token: gh auth login --with-token <<< 'your_token'"
        warning "2. Interactive login: gh auth login"
        echo ""
        read -p "Enter your GitHub PAT token (or press Enter to skip): " GH_TOKEN
        
        if [ -n "$GH_TOKEN" ]; then
            echo "$GH_TOKEN" | gh auth login --with-token
            if [ $? -eq 0 ]; then
                success "Authenticated with GitHub"
            else
                error "Authentication failed"
                read -p "Enter registration token manually: " REGISTRATION_TOKEN
            fi
        else
            warning "Skipping GitHub CLI authentication"
            warning "Generate token manually at:"
            warning "https://github.com/$GITHUB_REPO/settings/actions/runners/new"
            echo ""
            read -p "Enter registration token manually: " REGISTRATION_TOKEN
        fi
    else
        success "GitHub CLI already authenticated"
    fi
fi

# Try to generate token using gh CLI if authenticated and token not manually provided
if [ -z "$REGISTRATION_TOKEN" ] && command -v gh &> /dev/null && gh auth status &> /dev/null; then
    log "Attempting to generate token using gh CLI..."
    
    TOKEN_RESPONSE=$(gh api --method POST "repos/$GITHUB_REPO/actions/runners/registration-token" 2>&1)
    
    if [ $? -eq 0 ]; then
        REGISTRATION_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token')
        TOKEN_EXPIRES=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_at')
        
        success "Token generated successfully"
        log "Token expires: $TOKEN_EXPIRES"
    else
        error "Failed to generate token automatically"
        echo "$TOKEN_RESPONSE"
        echo ""
        warning "Generate token manually at:"
        warning "https://github.com/$GITHUB_REPO/settings/actions/runners/new"
        echo ""
        read -p "Enter registration token manually: " REGISTRATION_TOKEN
    fi
fi

if [ -z "$REGISTRATION_TOKEN" ]; then
    error "No registration token provided"
    exit 1
fi

log "Token length: ${#REGISTRATION_TOKEN} characters"

# Step 5: Configure runner
log ""
log "Step 5: Configuring runner..."
log "Runner will be configured with:"
log "  - Repository: https://github.com/$GITHUB_REPO"
log "  - Name: $TEST_RUNNER_NAME"
log "  - Labels: self-hosted,Linux,X64,test"
log ""

cd "$RUNNER_DIR"

# Remove old configuration if exists
if [ -f ".runner" ]; then
    warning "Runner appears to be already configured"
    log "Removing existing configuration..."
    sudo -u "$RUNNER_USER" ./config.sh remove --token "$REGISTRATION_TOKEN" 2>&1 || true
fi

# Configure with verbose output
log "Running configuration (this may take a moment)..."
echo ""
echo "=========================================="
echo "Configuration Output:"
echo "=========================================="

sudo -u "$RUNNER_USER" ./config.sh \
    --url "https://github.com/$GITHUB_REPO" \
    --token "$REGISTRATION_TOKEN" \
    --name "$TEST_RUNNER_NAME" \
    --labels "self-hosted,Linux,X64,test" \
    --unattended \
    --replace 2>&1 | tee /tmp/runner-config.log

CONFIG_EXIT_CODE=${PIPESTATUS[0]}

echo "=========================================="
echo ""

if [ $CONFIG_EXIT_CODE -eq 0 ]; then
    success "Runner configured successfully!"
    log ""
    log "Verification:"
    log "  - Check GitHub: https://github.com/$GITHUB_REPO/settings/actions/runners"
    log "  - Look for runner: $TEST_RUNNER_NAME"
    log ""
    
    # Step 6: Test runner
    log "Step 6: Testing runner connection..."
    log "Starting runner in test mode (will run for 10 seconds)..."
    
    timeout 10 sudo -u "$RUNNER_USER" ./run.sh 2>&1 || true
    
    log ""
    success "=========================================="
    success "✅ TEST COMPLETED SUCCESSFULLY"
    success "=========================================="
    log ""
    log "What to do next:"
    log "  1. Verify runner appears in GitHub UI"
    log "  2. If successful, this AMI is ready to use"
    log "  3. Stop the test runner: ./svc.sh stop"
    log "  4. Remove test runner: ./config.sh remove"
    log ""
    
else
    error "=========================================="
    error "❌ RUNNER CONFIGURATION FAILED"
    error "=========================================="
    log ""
    log "Checking configuration log for errors..."
    
    if grep -q "404" /tmp/runner-config.log; then
        error "Found 404 error in configuration log"
        error "This usually means:"
        error "  1. Runner version is too old (< 2.310.0)"
        error "  2. Using deprecated API endpoint"
        error "  3. Token is invalid or expired"
        
        if grep -q "api.github.com/actions/runner-registration" /tmp/runner-config.log; then
            error ""
            error "CRITICAL: Runner is using OLD API endpoint"
            error "  Old: https://api.github.com/actions/runner-registration"
            error "  New: https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token"
            error ""
            error "This confirms runner version is outdated"
            error "Runner binaries need to be updated to >= 2.310.0"
        fi
    fi
    
    if grep -q "401\|403" /tmp/runner-config.log; then
        error "Found authentication error"
        error "Check that token is valid and not expired"
    fi
    
    log ""
    log "Full configuration log:"
    cat /tmp/runner-config.log
    log ""
    
    exit 1
fi
