#!/bin/bash
set -euo pipefail
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# Configuration
PACKER_FILE="${1:-vm-vanilla-custom-user.pkr.hcl}"  # Default to vanilla with custom user
VM_NAME="${2:-custom-vm}"
echo -e "${GREEN}🔐 Tart VM Builder with 1Password${NC}"
echo "=================================="
echo "Usage: $0 [packer-file] [vm-name]"
echo "  packer-file: vm-vanilla-custom-user.pkr.hcl (default, recommended)"
echo "               vm-container-1password.pkr.hcl (vanilla, keeps default user)"
echo "               vm-ipsw-1password.pkr.hcl (fresh install, less reliable)"
echo ""
# Run validation first
echo -e "${YELLOW}Running environment validation...${NC}"
if ! ./validate-setup.sh --silent; then
    echo -e "${RED}❌ Environment validation failed${NC}"
    echo "Run './validate-setup.sh --verbose' for detailed information."
    exit 1
fi
echo -e "${GREEN}✓ Environment validation passed${NC}"
echo ""
# Dependencies already validated by validate-setup.sh
# 1Password authentication already validated
# Retrieve credentials from 1Password (credentials already validated)
echo -e "${YELLOW}Retrieving credentials from 1Password...${NC}"
export PKR_VAR_ssh_username="$(op read 'op://Private/Packer Automations/username')"
export PKR_VAR_ssh_password="$(op read 'op://Private/Packer Automations/password')"
export PKR_VAR_ssh_public_key="$(op read 'op://Private/Packer Automations/public key')"
echo -e "${GREEN}✓ Credentials retrieved successfully${NC}"
# Initialize Packer
echo -e "\n${YELLOW}Initializing Packer...${NC}"
packer init "$PACKER_FILE"
# Build the VM
echo -e "\n${YELLOW}Building VM: $VM_NAME${NC}"
echo "This may take several minutes..."

# Enable verbose Packer logging
export PACKER_LOG=1

if packer build \
    -var "vm_name=$VM_NAME" \
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