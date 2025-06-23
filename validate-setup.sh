#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SILENT=false
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--silent) SILENT=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        *) break ;;
    esac
done

# Output only in verbose mode or on failure
if [ "$VERBOSE" = true ]; then
    echo -e "${BLUE}🔍 VM Builder Environment Validator${NC}"
    echo "===================================="
fi

VALIDATION_PASSED=true
FAILURES=()

# Function to report test results
report_test() {
    local test_name="$1"
    local passed="$2"
    local message="$3"
    
    if [ "$passed" = true ]; then
        if [ "$VERBOSE" = true ]; then
            echo -e "${GREEN}✓${NC} $test_name"
        fi
    else
        FAILURES+=("$test_name: $message")
        VALIDATION_PASSED=false
        if [ "$VERBOSE" = true ]; then
            echo -e "${RED}✗${NC} $test_name: $message"
        fi
    fi
}

# Silent section divider for verbose mode
section() {
    if [ "$VERBOSE" = true ]; then
        echo -e "\n${YELLOW}$1...${NC}"
    fi
}

section "Checking Dependencies"

# Check for required tools
for tool in op packer tart ssh-keygen jq; do
    if command -v "$tool" &> /dev/null; then
        report_test "Found $tool" true ""
    else
        case "$tool" in
            op) suggest="brew install 1password-cli" ;;
            packer) suggest="brew install hashicorp/tap/packer" ;;
            tart) suggest="brew install cirruslabs/cli/tart" ;;
            ssh-keygen) suggest="Should be pre-installed on macOS" ;;
            jq) suggest="brew install jq" ;;
        esac
        report_test "Found $tool" false "Install with: $suggest"
    fi
done

section "Testing 1Password Connectivity"

# Check 1Password CLI authentication
if op account list &> /dev/null; then
    report_test "1Password authentication" true ""
    
    # Check if required item exists
    if op item get "Packer Automations" --vault Private &> /dev/null; then
        report_test "1Password item 'Packer Automations' exists" true ""
        
        # Check required fields exist
        ITEM_JSON=$(op item get "Packer Automations" --vault Private --format json)
        
        # Check for username field
        if echo "$ITEM_JSON" | jq -e '.fields[] | select(.label == "username")' &> /dev/null; then
            report_test "1Password item has 'username' field" true ""
        else
            report_test "1Password item has 'username' field" false "Add with: op item edit 'Packer Automations' --vault Private username=admin"
        fi
        
        # Check for password field  
        if echo "$ITEM_JSON" | jq -e '.fields[] | select(.label == "password")' &> /dev/null; then
            report_test "1Password item has 'password' field" true ""
        else
            report_test "1Password item has 'password' field" false "Add with: op item edit 'Packer Automations' --vault Private password='SecurePass123!'"
        fi
        
        # Check for public key field
        if echo "$ITEM_JSON" | jq -e '.fields[] | select(.label == "public key")' &> /dev/null; then
            report_test "1Password item has 'public key' field" true ""
            
            # Validate SSH key format
            PUBLIC_KEY=$(op read 'op://Private/Packer Automations/public key' 2>/dev/null || echo "")
            if [ -n "$PUBLIC_KEY" ]; then
                # Basic SSH key format validation
                if echo "$PUBLIC_KEY" | grep -E '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) [A-Za-z0-9+/]+=*' &> /dev/null; then
                    report_test "SSH key format validation" true ""
                    
                    # Test key validation by writing to temp file
                    TEMP_KEY_FILE=$(mktemp)
                    echo "$PUBLIC_KEY" > "$TEMP_KEY_FILE"
                    if ssh-keygen -l -f "$TEMP_KEY_FILE" &> /dev/null; then
                        report_test "SSH key cryptographic validation" true ""
                    else
                        report_test "SSH key cryptographic validation" false "Key appears malformed (ssh-keygen validation failed)"
                    fi
                    rm "$TEMP_KEY_FILE"
                else
                    report_test "SSH key format validation" false "Should start with 'ssh-rsa', 'ssh-ed25519', etc. and contain base64 content"
                fi
            else
                report_test "SSH key content accessibility" false "Could not read public key from 1Password"
            fi
        else
            report_test "1Password item has 'public key' field" false "Add with: op item edit 'Packer Automations' --vault Private 'public key=\$(cat ~/.ssh/id_rsa.pub)'"
        fi
        
    else
        report_test "1Password item 'Packer Automations' exists" false "Create with: op item create --category=login --title='Packer Automations' --vault=Private"
    fi
else
    report_test "1Password authentication" false "Sign in with: op signin"
fi

section "Validating Packer Manifests"

# Check Packer manifest syntax
for manifest in vm-ipsw-1password.pkr.hcl vm-container-1password.pkr.hcl; do
    if [ -f "$manifest" ]; then
        # Basic syntax validation using packer validate (skip variable validation)
        if packer validate -syntax-only "$manifest" &> /dev/null; then
            report_test "Packer manifest syntax: $manifest" true ""
        else
            # Try to provide more specific error info
            PACKER_ERROR=$(packer validate "$manifest" 2>&1 || true)
            if echo "$PACKER_ERROR" | grep -i "required plugins" &> /dev/null; then
                report_test "Packer manifest syntax: $manifest" false "Run 'packer init $manifest' first to download plugins"
            else
                report_test "Packer manifest syntax: $manifest" false "Syntax error (run 'packer validate $manifest' for details)"
            fi
        fi
        
        # Check for sensitive variable handling
        if grep -E "default.*=.*['\"].*['\"]" "$manifest" | grep -vE "(latest|vanilla|base)" | grep -E "(password|username|key)" &> /dev/null; then
            report_test "Security check: $manifest" false "Found hardcoded credentials in manifest (check variable defaults)"
        else
            report_test "Security check: $manifest" true ""
        fi
    else
        report_test "Packer manifest exists: $manifest" false "File is missing"
    fi
done

# Check build script
if [ -f "build-with-1password.sh" ]; then
    if [ -x "build-with-1password.sh" ]; then
        report_test "Build script executable" true ""
    else
        report_test "Build script executable" false "Make executable with: chmod +x build-with-1password.sh"
    fi
    
    # Basic shellcheck if available
    if command -v shellcheck &> /dev/null; then
        if shellcheck -S error "build-with-1password.sh" &> /dev/null; then
            report_test "Build script syntax check" true ""
        else
            report_test "Build script syntax check" false "Run 'shellcheck build-with-1password.sh' for details"
        fi
    fi
else
    report_test "Build script exists" false "build-with-1password.sh is missing"
fi

section "Environment Requirements"

# Check disk space (rough estimate: 50GB for IPSW build)
AVAILABLE_SPACE_KB=$(df . | tail -1 | awk '{print $4}')
AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE_KB / 1024 / 1024))

if [ "$AVAILABLE_SPACE_GB" -ge 50 ]; then
    report_test "Disk space (50GB+ recommended)" true "Available: ${AVAILABLE_SPACE_GB}GB"
else
    report_test "Disk space (50GB+ recommended)" false "Available: ${AVAILABLE_SPACE_GB}GB (may be insufficient for IPSW builds)"
fi

# Check memory (rough estimate: 8GB+ system RAM recommended)
TOTAL_MEMORY_KB=$(sysctl hw.memsize | awk '{print $2}')
TOTAL_MEMORY_GB=$((TOTAL_MEMORY_KB / 1024 / 1024 / 1024))

if [ "$TOTAL_MEMORY_GB" -ge 8 ]; then
    report_test "System memory (8GB+ recommended)" true "Available: ${TOTAL_MEMORY_GB}GB"
else
    report_test "System memory (8GB+ recommended)" false "Available: ${TOTAL_MEMORY_GB}GB (may cause performance issues)"
fi

# Check if we're on Apple Silicon (required for Tart)
if sysctl -n machdep.cpu.brand_string | grep -i "apple" &> /dev/null; then
    report_test "Apple Silicon CPU" true ""
else
    report_test "Apple Silicon CPU" false "Tart requires Apple Silicon (M1/M2/M3/M4)"
fi

# Check macOS version (Tart requires macOS 13.0+)
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [ "$MACOS_MAJOR" -ge 13 ]; then
    report_test "macOS version (13.0+ required)" true "Running: $MACOS_VERSION"
else
    report_test "macOS version (13.0+ required)" false "Running: $MACOS_VERSION (too old)"
fi

# Results handling
if [ "$VALIDATION_PASSED" = true ]; then
    if [ "$SILENT" = false ]; then
        echo -e "${GREEN}✅ Environment validation passed${NC} - Ready to build VMs"
    fi
    exit 0
else
    echo -e "${RED}❌ Environment validation failed${NC}"
    echo ""
    echo "Found ${#FAILURES[@]} issue(s):"
    for failure in "${FAILURES[@]}"; do
        echo -e "  ${RED}•${NC} $failure"
    done
    echo ""
    echo -e "${BLUE}Tip:${NC} Run with --verbose flag for detailed output"
    echo "      Fix issues above, then run ./build-with-1password.sh"
    exit 1
fi