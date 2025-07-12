#!/bin/bash
set -euo pipefail

# Early argument parsing for --help
for arg in "$@"; do
    case $arg in
        --help|-h)
            echo "🔐 Tart VM Builder with 1Password"
            echo "=================================="
            echo ""
            echo "Usage: $0 [packer-file] [vm-name]"
            echo "  packer-file: vm-vanilla-custom-user.pkr.hcl (default, recommended)"
            echo "               vm-container-1password.pkr.hcl (vanilla, keeps default user)"
            echo "               vm-ipsw-1password.pkr.hcl (fresh install, less reliable)"
            echo ""
            echo "Environment variable overrides:"
            echo "  CONFIG_FILE - Custom config file path"
            echo "  VM_NAME_OVERRIDE - Override VM name"
            echo "  PACKER_FILE_OVERRIDE - Override Packer file"
            echo "  OP_VAULT_OVERRIDE - Override 1Password vault"
            echo "  OP_ITEM_OVERRIDE - Override 1Password item"
            echo "  OP_ACCOUNT_OVERRIDE - Override 1Password account"
            echo ""
            echo "Examples:"
            echo "  $0 --help                     # Show this help"
            echo "  $0                            # Use defaults from config"
            echo "  $0 vm-vanilla-custom-user.pkr.hcl my-vm  # Specify file and name"
            echo ""
            exit 0
            ;;
    esac
done

# Configuration loading
CONFIG_FILE="${CONFIG_FILE:-config/default.toml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/$CONFIG_FILE"

# Function to parse TOML config
parse_config() {
    local key="$1"
    python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print('Error: Neither tomllib nor tomli is available', file=sys.stderr)
        print('Install with: pip3 install tomli', file=sys.stderr)
        sys.exit(1)

try:
    with open('$CONFIG_PATH', 'rb') as f:
        config = tomllib.load(f)
    
    # Navigate nested keys (e.g., 'vm.defaults.name')
    keys = '$key'.split('.')
    value = config
    for k in keys:
        value = value[k]
    
    print(value)
except Exception as e:
    print(f'Error parsing config key \"$key\": {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Load configuration or fallback to defaults
load_config() {
    if [[ -f "$CONFIG_PATH" ]]; then
        echo "Loading configuration from: $CONFIG_PATH" >&2
        
        # Load all configuration values
        PACKER_FILE="${1:-$(parse_config 'build.default_packer_file')}"
        VM_NAME="${2:-$(parse_config 'vm.defaults.name')}"
        
        # 1Password configuration
        OP_VAULT="$(parse_config 'onepassword.vault')"
        OP_ITEM="$(parse_config 'onepassword.item')"
        OP_ACCOUNT="$(parse_config 'onepassword.account')"
        OP_USERNAME_FIELD="$(parse_config 'onepassword.username_field')"
        OP_PASSWORD_FIELD="$(parse_config 'onepassword.password_field')"
        OP_PUBLIC_KEY_FIELD="$(parse_config 'onepassword.public_key_field')"
        
        # Packer configuration
        PACKER_LOG="$(parse_config 'packer.log_level')"
        
        # Build configuration
        COLORS="$(parse_config 'build.colors')"
        VERBOSE_VALIDATION="$(parse_config 'build.verbose_validation')"
    else
        echo "Warning: Configuration file not found at $CONFIG_PATH, using defaults" >&2
        
        # Fallback to original hardcoded values
        PACKER_FILE="${1:-vm-vanilla-custom-user.pkr.hcl}"
        VM_NAME="${2:-custom-vm}"
        OP_VAULT="Private"
        OP_ITEM="Packer Automations"
        OP_ACCOUNT="iaconelli.1password.com"
        OP_USERNAME_FIELD="username"
        OP_PASSWORD_FIELD="password"
        OP_PUBLIC_KEY_FIELD="public key"
        PACKER_LOG="1"
        COLORS="true"
        VERBOSE_VALIDATION="false"
    fi
}

# Colors for output
if [[ "${COLORS:-true}" == "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Load configuration
load_config "$@"

# Allow environment variable overrides
VM_NAME="${VM_NAME_OVERRIDE:-$VM_NAME}"
PACKER_FILE="${PACKER_FILE_OVERRIDE:-$PACKER_FILE}"
OP_VAULT="${OP_VAULT_OVERRIDE:-$OP_VAULT}"
OP_ITEM="${OP_ITEM_OVERRIDE:-$OP_ITEM}"
OP_ACCOUNT="${OP_ACCOUNT_OVERRIDE:-$OP_ACCOUNT}"

# Configuration validation function
validate_config() {
    local errors=0
    
    # Check if configuration file exists and is readable
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo -e "${YELLOW}Warning: Configuration file not found at $CONFIG_PATH${NC}" >&2
        return 0  # Non-fatal, we have fallbacks
    fi
    
    # Check if Packer file exists
    if [[ ! -f "$PACKER_FILE" ]]; then
        echo -e "${RED}Error: Packer file '$PACKER_FILE' not found${NC}" >&2
        ((errors++))
    fi
    
    # Validate VM name format
    if [[ ! "$VM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: VM name '$VM_NAME' contains invalid characters. Use only alphanumeric, underscore, and hyphen.${NC}" >&2
        ((errors++))
    fi
    
    # Check for tomllib availability
    if ! python3 -c "import tomllib" 2>/dev/null && ! python3 -c "import tomli" 2>/dev/null; then
        if [[ -f "$CONFIG_PATH" ]]; then
            echo -e "${RED}Error: Python TOML library not available. Install with: pip3 install tomli${NC}" >&2
            ((errors++))
        fi
    fi
    
    return $errors
}
echo -e "${GREEN}🔐 Tart VM Builder with 1Password${NC}"
echo "=================================="
echo "Using configuration: $CONFIG_PATH"
echo "Packer file: $PACKER_FILE"
echo "VM name: $VM_NAME"
echo "1Password: $OP_VAULT/$OP_ITEM"
echo ""

# Validate configuration
echo -e "${YELLOW}Validating configuration...${NC}"
if ! validate_config; then
    echo -e "${RED}❌ Configuration validation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Configuration validation passed${NC}"
echo ""
# Run validation first
echo -e "${YELLOW}Running environment validation...${NC}"
VALIDATION_ARGS=""
if [[ "$VERBOSE_VALIDATION" == "true" ]]; then
    VALIDATION_ARGS="--verbose"
else
    VALIDATION_ARGS="--silent"
fi

if ! ./validate-setup.sh $VALIDATION_ARGS; then
    echo -e "${RED}❌ Environment validation failed${NC}"
    echo "Run './validate-setup.sh --verbose' for detailed information."
    exit 1
fi
echo -e "${GREEN}✓ Environment validation passed${NC}"
echo ""

# Dependencies already validated by validate-setup.sh
# 1Password authentication already validated
# Retrieve credentials from 1Password using configurable paths
echo -e "${YELLOW}Retrieving credentials from 1Password...${NC}"
OP_USERNAME_PATH="op://$OP_VAULT/$OP_ITEM/$OP_USERNAME_FIELD"
OP_PASSWORD_PATH="op://$OP_VAULT/$OP_ITEM/$OP_PASSWORD_FIELD"  
OP_PUBLIC_KEY_PATH="op://$OP_VAULT/$OP_ITEM/$OP_PUBLIC_KEY_FIELD"

export PKR_VAR_ssh_username="$(op read "$OP_USERNAME_PATH" --account "$OP_ACCOUNT")"
export PKR_VAR_ssh_password="$(op read "$OP_PASSWORD_PATH" --account "$OP_ACCOUNT")"
export PKR_VAR_ssh_public_key="$(op read "$OP_PUBLIC_KEY_PATH" --account "$OP_ACCOUNT")"
echo -e "${GREEN}✓ Credentials retrieved successfully${NC}"
# Initialize Packer
echo -e "\n${YELLOW}Initializing Packer...${NC}"
packer init "$PACKER_FILE"
# Build the VM
echo -e "\n${YELLOW}Building VM: $VM_NAME${NC}"
echo "This may take several minutes..."

# Configure Packer logging from config
export PACKER_LOG="$PACKER_LOG"

# Build Packer variables from configuration
PACKER_VARS=""
if [[ -f "$CONFIG_PATH" ]]; then
    # VM configuration
    PACKER_VARS="$PACKER_VARS -var cpu_count=$(parse_config 'vm.defaults.cpu_count')"
    PACKER_VARS="$PACKER_VARS -var memory_gb=$(parse_config 'vm.defaults.memory_gb')"
    PACKER_VARS="$PACKER_VARS -var disk_size_gb=$(parse_config 'vm.defaults.disk_size_gb')"
    
    # Timing configuration
    PACKER_VARS="$PACKER_VARS -var system_settle_delay=$(parse_config 'timing.system_settle_delay')"
    
    # Build configuration
    PACKER_VARS="$PACKER_VARS -var headless_mode=$(parse_config 'build.headless_mode')"
    
    # File-specific configurations
    case "$PACKER_FILE" in
        *vanilla-custom*)
            PACKER_VARS="$PACKER_VARS -var base_image=$(parse_config 'vm.vanilla.base_image')"
            PACKER_VARS="$PACKER_VARS -var ssh_timeout=$(parse_config 'ssh.timeout_vanilla')"
            PACKER_VARS="$PACKER_VARS -var tart_version=$(parse_config 'packer.tart_version_vanilla')"
            PACKER_VARS="$PACKER_VARS -var default_username=$(parse_config 'vm.vanilla.default_username')"
            PACKER_VARS="$PACKER_VARS -var default_password=$(parse_config 'vm.vanilla.default_password')"
            PACKER_VARS="$PACKER_VARS -var initial_wait=$(parse_config 'timing.initial_wait')"
            PACKER_VARS="$PACKER_VARS -var connection_retry_delay=$(parse_config 'timing.connection_retry_delay')"
            ;;
        *container*)
            PACKER_VARS="$PACKER_VARS -var base_image=$(parse_config 'vm.vanilla.base_image')"
            PACKER_VARS="$PACKER_VARS -var ssh_timeout=$(parse_config 'ssh.timeout_container')"
            PACKER_VARS="$PACKER_VARS -var tart_version=$(parse_config 'packer.tart_version_vanilla')"
            ;;
        *ipsw*)
            PACKER_VARS="$PACKER_VARS -var ipsw_url=$(parse_config 'vm.ipsw.url')"
            PACKER_VARS="$PACKER_VARS -var ssh_timeout=$(parse_config 'ssh.timeout_ipsw')"
            PACKER_VARS="$PACKER_VARS -var tart_version=$(parse_config 'packer.tart_version_ipsw')"
            PACKER_VARS="$PACKER_VARS -var boot_wait=$(parse_config 'timing.boot_wait')"
            PACKER_VARS="$PACKER_VARS -var boot_key_interval=$(parse_config 'timing.boot_key_interval')"
            ;;
    esac
    
    # Common Packer plugin configuration
    PACKER_VARS="$PACKER_VARS -var tart_source=$(parse_config 'packer.tart_source')"
fi

if packer build \
    -var "vm_name=$VM_NAME" \
    $PACKER_VARS \
    "$PACKER_FILE"; then
    
    echo -e "\n${GREEN}✅ VM build complete!${NC}"
    echo
    echo "Your VM '$VM_NAME' is ready to use:"
    echo "  Start VM:  tart run $VM_NAME"
    echo "  Get IP:    tart ip $VM_NAME"
    echo "  SSH:       ssh $PKR_VAR_ssh_username@\$(tart ip $VM_NAME)"
    echo "  VNC:       vnc://$PKR_VAR_ssh_username@\$(tart ip $VM_NAME)"
    echo
    echo "To start the VM with VNC in headless mode:"
    echo "  tart run $VM_NAME --no-graphics --vnc"
else
    echo -e "\n${RED}❌ Build failed${NC}"
    exit 1
fi