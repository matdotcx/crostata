# Tart VM Builder with 1Password

This project provides scripts and Packer manifests for creating macOS virtual machines using Tart, with secure credential management via 1Password.

## Why Use This?

**Problem this solves:** Creating macOS VMs with Tart is powerful but has pain points:
- Hardcoded credentials in configuration files (security risk)
- Complex manual setup process each time
- SSH key management across multiple machines
- Inconsistent VM configurations across team members

**This solution provides:**
- **Automated builds**: Single command creates fully configured VMs (15-30 minutes)
- **Secure credentials**: No hardcoded passwords, all stored in 1Password
- **Team-ready**: Share secure VM configurations without sharing secrets
- **Two approaches**: Fresh IPSW install vs. fast container-based builds

**Use cases:**
- Development environments isolated from your main system
- Software testing across macOS versions
- CI/CD build environments
- Security testing sandboxes
- Cross-team standardized environments

## Prerequisites

### Required Software
- **1Password CLI** (`op`): Install via `brew install 1password-cli`
- **Packer**: Install via `brew install hashicorp/tap/packer`  
- **Tart**: Install via `brew install cirruslabs/cli/tart`
- **jq**: Install via `brew install jq` (for 1Password JSON parsing)

**Hardware Requirements:**
- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 13.0+ (Ventura or newer)
- 8GB+ RAM (for VM performance)
- 50GB+ free disk space (for IPSW builds)

### 1Password Setup
Create an item in your **Private** vault called **"Packer Automations"** with these exact field names:

| Field Name | Type | Purpose | Example |
|------------|------|---------|---------|
| `username` | Text | SSH username for the VM | `admin` |
| `password` | Password | SSH password for the VM | `SecurePass123!` |  
| `public key` | Text | Full SSH public key content | `ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB...` |

**Quick setup via CLI:**
```bash
# Generate SSH key if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vm_key -N ""

# Create 1Password item with all fields
op item create \
  --category=login \
  --title="Packer Automations" \
  --vault=Private \
  username=admin \
  password="SecureVMPassword123!" \
  "public key=$(cat ~/.ssh/vm_key.pub)"
```

## Available Manifests

### vm-ipsw-1password.pkr.hcl (IPSW-based)
- **Source**: Downloads macOS IPSW files (latest by default)
- **Setup**: Automated macOS Setup Assistant walkthrough
- **Features**: Clean macOS installation with custom user account
- **Default**: Used by `build-with-1password.sh`

### vm-container-1password.pkr.hcl (Container-based)
- **Source**: `ghcr.io/cirruslabs/macos-sequoia-vanilla:latest`
- **Setup**: Quick setup on pre-installed macOS
- **Features**: Optimized for development workflows with 1Password security

## Quick Start

### Basic Usage
```bash
./build-with-1password.sh
```
Creates a VM named `custom-vm` using `vm-ipsw-1password.pkr.hcl` manifest. Environment validation runs automatically first.

### Manual Validation
```bash
./validate-setup.sh           # Default: shows "✅ Environment validation passed" 
./validate-setup.sh --verbose # Shows detailed results for all checks
./validate-setup.sh --silent  # Completely silent, exit code only
```

### Custom Configuration
```bash
./build-with-1password.sh [manifest] [vm-name]
```

Examples:
```bash
./build-with-1password.sh vm-ipsw-1password.pkr.hcl dev-vm
./build-with-1password.sh vm-container-1password.pkr.hcl test-vm
```

## Build Process

### Validation Phase
1. **Environment validation**: Dependencies, 1Password connectivity, SSH key format, Packer manifests, system requirements
2. **Credential retrieval**: Pulls secure credentials from 1Password vault (already validated)

### VM Creation Phase
1. **IPSW Download** (vm-ipsw-1password.pkr.hcl): Downloads latest macOS IPSW automatically
2. **Packer Initialization**: Downloads required plugins
3. **VM Provisioning**: Creates base VM with specified resources

### Setup Phase (IPSW-based only)
1. **Automated macOS Setup**: Boot commands navigate Setup Assistant
   - Language and region selection
   - Skips Apple ID, analytics, Siri
   - Creates user account with 1Password credentials
2. **System Configuration**: Shell provisioners apply:
   - SSH key installation and service enablement
   - VNC/Screen Sharing configuration
   - System optimizations (disable sleep, spotlight, updates)
   - Passwordless sudo and auto-login setup

## VM Specifications

### Default Resources
- **CPU**: 4 cores
- **Memory**: 8GB
- **Disk**: 50GB

### Customization
Modify manifest files or create custom `.pkrvars.hcl` files to adjust:
- Resource allocation
- Base image source
- System configurations
- Provisioning scripts

## VM Management

### Starting the VM
```bash
tart run [vm-name]
```

### Connecting via SSH
```bash
ssh [username]@$(tart ip [vm-name])
```

### Connecting via VNC
```bash
vnc://[username]@$(tart ip [vm-name])
```

### Headless Mode with VNC
```bash
tart run [vm-name] --no-graphics --vnc
```

### Getting VM IP
```bash
tart ip [vm-name]
```

## Security Features

### Credential Management
- Credentials stored securely in 1Password vault
- No hardcoded passwords in manifests
- SSH key-based authentication enabled by default

### System Hardening
- Passwordless sudo configured for convenience
- Automatic updates disabled
- Screen locking disabled for VM usability
- Spotlight indexing disabled for performance

## Manifest Comparison

| Feature | vm-ipsw-1password.pkr.hcl | vm-container-1password.pkr.hcl |
|---------|---------------------------|--------------------------------|
| Base Source | IPSW | GHCR Container |
| Setup Process | Automated macOS | Quick |
| Credentials | 1Password | 1Password |
| SSH Setup | Automated | Manual |
| VNC Setup | Automated | Manual |
| Auto-login | Yes | No |
| Boot Time | Longer (full install) | Faster (pre-installed) |
| Disk Usage | More space (fresh install) | Less space (optimized) |
| Build Time | ~15-30 minutes | ~5-10 minutes |
| Reliability | High (clean OS install) | Medium (dependency on GHCR) |
| Best For | Clean environments, testing | Quick dev iteration |

## Troubleshooting

### Environment Validation Issues
**Before build problems occur**, the validation system catches:
- **Missing dependencies**: Specific `brew install` commands provided
- **1Password connectivity**: Sign-in prompts and item setup instructions  
- **SSH key format problems**: Pattern and cryptographic validation with specific fixes
- **Packer manifest syntax**: Syntax validation with `packer init` suggestions
- **System requirements**: Disk space, memory, CPU, and macOS version warnings

**Quick diagnosis:**
```bash
./validate-setup.sh --verbose  # Shows all 20+ checks with ✓/✗ results
```

### Build-time Issues
- **IPSW download fails**: Check internet connectivity and disk space (50GB+)
- **VM boot hangs**: Try deleting VM and rebuilding: `tart delete [vm-name]`
- **Packer timeout**: Increase `ssh_timeout` in manifest file
- **VNC authentication fails**: Check Screen Sharing is enabled in VM

### Build Logs
Packer provides detailed logs during build. Monitor output for specific error messages.

### VM Access Issues
- Verify VM is running: `tart list`
- Check IP assignment: `tart ip [vm-name]`
- Test SSH connectivity: `ssh -v [username]@[ip]`
- **SSH key rejected**: Re-validate key format: `./validate-setup.sh --verbose`

## File Structure

```
.
├── README.md                        # This documentation
├── LICENSE                          # MIT license
├── .gitignore                       # Security-focused git excludes
├── validate-setup.sh                # Pre-build environment validation script
├── build-with-1password.sh          # Main build script with 1Password integration
├── vm-ipsw-1password.pkr.hcl        # IPSW-based VM manifest (default)
├── vm-container-1password.pkr.hcl   # Container-based VM with 1Password
└── vm-config.pkrvars.hcl            # Configuration variables (non-sensitive only)
```

**Note:** The `.pkrvars.hcl` file is included for configuration examples but ignored by git for security. Do not store credentials there - use 1Password instead.

## Advanced Configuration

### Custom IPSW Sources
Edit `vm-ipsw-1password.pkr.hcl` to specify:
- **Specific URL**: Replace `default = "latest"` with IPSW URL
- **Local file**: Use path like `~/Downloads/macOS.ipsw`

### Resource Allocation
Modify variables in manifest files:
- `cpu_count`: CPU cores
- `memory_gb`: RAM in gigabytes  
- `disk_size_gb`: Disk space in gigabytes

### System Optimizations
Shell provisioners can be customized to:
- Add development tools
- Configure network settings
- Install additional software
- Modify system preferences

## Contributing

Issues and PRs welcome! This project aims to be community-driven.

**Areas for improvement:**
- Test boot commands on different macOS versions
- Add more VM configuration examples  
- Performance optimizations for build times
- Alternative credential storage methods (macOS Keychain, AWS Secrets Manager)
- Add container manifest with automated SSH/VNC setup like IPSW version
- Support for different VM base images (Linux variants)

**Development guidelines:**
- All credentials must use 1Password (no hardcoded secrets)
- Shell scripts should use `set -euo pipefail` for safety
- New features should include validation in `validate-setup.sh`
- Document any new 1Password field requirements clearly

## License

MIT License - see [LICENSE](LICENSE) file for details.