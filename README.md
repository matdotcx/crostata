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

### vm-vanilla-custom-user.pkr.hcl (Vanilla with Custom User) - **Recommended**
- **Source**: `ghcr.io/cirruslabs/macos-sequoia-vanilla:latest`
- **Setup**: Connects with default credentials, creates custom user, removes default
- **Features**: Clean vanilla macOS with only your custom user
- **Default**: Used by `build-with-1password.sh`
- **Benefits**: 
  - No leftover default accounts
  - Clean system without Homebrew or development tools
  - Fast build time (5-10 minutes)
  - Most secure approach

### vm-ipsw-1password.pkr.hcl (IPSW-based)
- **Source**: Downloads macOS IPSW files (latest by default)
- **Setup**: Automated macOS Setup Assistant walkthrough
- **Features**: Clean macOS installation with custom user account
- **Build time**: 15-30 minutes

### vm-container-1password.pkr.hcl (Container-based)
- **Source**: `ghcr.io/cirruslabs/macos-sequoia-vanilla:latest`
- **Setup**: Quick setup on pre-installed macOS
- **Features**: Keeps default admin user alongside custom user

## Quick Start

### Basic Usage
```bash
./build-with-1password.sh
```
Creates a VM named `custom-vm` using `vm-vanilla-custom-user.pkr.hcl` manifest. Environment validation runs automatically first.

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
./build-with-1password.sh vm-vanilla-custom-user.pkr.hcl dev-vm
./build-with-1password.sh vm-ipsw-1password.pkr.hcl fresh-vm
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

### Running VM in Background
```bash
# Option 1: Using nohup
nohup tart run [vm-name] --no-graphics > /dev/null 2>&1 &

# Option 2: Using disown
tart run [vm-name] --no-graphics &
disown

# Option 3: Using launchd (persistent across reboots)
cat > ~/Library/LaunchAgents/com.tart.[vm-name].plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tart.[vm-name]</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/tart</string>
        <string>run</string>
        <string>[vm-name]</string>
        <string>--no-graphics</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/tart-[vm-name].log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/tart-[vm-name].error.log</string>
</dict>
</plist>
EOF

# Load and start
launchctl load ~/Library/LaunchAgents/com.tart.[vm-name].plist
launchctl start com.tart.[vm-name]

# To stop: launchctl stop com.tart.[vm-name]
# To remove: launchctl unload ~/Library/LaunchAgents/com.tart.[vm-name].plist
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

| Feature | vm-vanilla-custom-user.pkr.hcl | vm-ipsw-1password.pkr.hcl | vm-container-1password.pkr.hcl |
|---------|--------------------------------|---------------------------|--------------------------------|
| Base Source | GHCR Container | IPSW | GHCR Container |
| Setup Process | Replace default user | Automated macOS | Keep default user |
| Default User | **Removed completely** | Never created | Kept alongside custom |
| Credentials | 1Password | 1Password | 1Password |
| SSH Setup | Automated | Automated | Manual |
| VNC Setup | Automated | Automated | Manual |
| Homebrew | **Not installed** | Not installed | Not installed |
| Boot Time | Fast | Longer (full install) | Fast |
| Build Time | ~5-10 minutes | ~15-30 minutes | ~5-10 minutes |
| Security | **Highest** (single user) | High (clean OS) | Medium (dual users) |
| Best For | **Production, secure envs** | Clean testing | Quick dev iteration |

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
├── validate-config.py               # Configuration validation script
├── vm-vanilla-custom-user.pkr.hcl   # Vanilla VM with custom user only (default)
├── vm-ipsw-1password.pkr.hcl        # IPSW-based VM manifest (clean install)
├── vm-container-1password.pkr.hcl   # Container-based VM with 1Password
└── config/
    ├── default.toml                 # Centralized configuration file
    └── schema.json                  # JSON schema for configuration validation
```

**Configuration Management:**
- `config/default.toml` - All hardcoded values moved to centralized configuration
- `config/schema.json` - Type-safe validation schema for configurations
- `validate-config.py` - Validates configuration files against schema
- Environment variables provide runtime overrides without file modification

## Configuration Management

### Centralized Configuration
The VM builder uses a centralized TOML configuration file at `config/default.toml` that eliminates hardcoded values and makes the system highly configurable.

**Key benefits:**
- **No hardcoded values**: All configuration centralized in `config/default.toml`
- **Environment overrides**: Override any setting with environment variables
- **Type safety**: JSON schema validation ensures configuration correctness
- **Backward compatibility**: Falls back to original defaults if config missing

### Configuration File Structure

```toml
[onepassword]
vault = "Private"                    # 1Password vault name
item = "Packer Automations"         # 1Password item name
username_field = "username"         # Field names within the item
password_field = "password"
public_key_field = "public key"

[vm.defaults]
name = "custom-vm"                   # Default VM name
cpu_count = 4                        # Number of CPU cores
memory_gb = 8                        # Memory in GB
disk_size_gb = 50                    # Disk size in GB

[vm.vanilla]
base_image = "ghcr.io/cirruslabs/macos-sequoia-vanilla:latest"
default_username = "admin"           # Default vanilla image credentials
default_password = "admin"

[vm.ipsw]
url = "latest"                       # IPSW source: "latest", URL, or local path

[packer]
tart_version_vanilla = ">= 0.5.3"    # Plugin versions for different builds
tart_version_ipsw = ">= 1.12.0"
tart_source = "github.com/cirruslabs/tart"
log_level = "1"                      # 0=quiet, 1=verbose

[ssh]
timeout_vanilla = "120s"             # SSH timeouts for different builds
timeout_ipsw = "1200s"
timeout_container = "120s"

[timing]
system_settle_delay = 10             # Various timing configurations
initial_wait = 30
connection_retry_delay = 5
boot_wait = "180s"                   # IPSW-specific boot timing
boot_key_interval = "50ms"

[system]
disable_sleep = true                 # System optimization flags
disable_spotlight = true
enable_ssh = true
enable_vnc = true
# ... more system settings

[build]
default_packer_file = "vm-vanilla-custom-user.pkr.hcl"
headless_mode = true
colors = true                        # Enable colored output
```

### Environment Variable Overrides

Override any configuration value using environment variables:

```bash
# Override VM configuration
VM_NAME_OVERRIDE="dev-vm" ./build-with-1password.sh

# Use custom configuration file
CONFIG_FILE="config/production.toml" ./build-with-1password.sh

# Override 1Password settings
OP_VAULT_OVERRIDE="Development" ./build-with-1password.sh

# Override Packer file
PACKER_FILE_OVERRIDE="vm-ipsw-1password.pkr.hcl" ./build-with-1password.sh
```

### Configuration Validation

Validate your configuration against the JSON schema:

```bash
# Basic validation
python3 validate-config.py

# Verbose validation with detailed output
python3 validate-config.py --verbose

# Custom config and schema files
python3 validate-config.py --config config/custom.toml --schema config/schema.json
```

### Creating Custom Configurations

1. **Copy the default configuration:**
   ```bash
   cp config/default.toml config/production.toml
   ```

2. **Modify settings for your environment:**
   ```toml
   [vm.defaults]
   cpu_count = 8        # More powerful VMs
   memory_gb = 16
   
   [onepassword]
   vault = "Development"  # Different 1Password vault
   
   [build]
   colors = false       # Disable colors for CI/CD
   ```

3. **Use the custom configuration:**
   ```bash
   CONFIG_FILE="config/production.toml" ./build-with-1password.sh
   ```

### Advanced Customization

#### Custom IPSW Sources
Configure IPSW downloads in `config/default.toml`:
```toml
[vm.ipsw]
# Use latest macOS (default)
url = "latest"

# Use specific IPSW URL
url = "https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-16517/AACDDC33-9683-4431-98AF-F04EF7C15EE3/UniversalMac_15.4_24E248_Restore.ipsw"

# Use local IPSW file
url = "~/Downloads/UniversalMac_15.4_24E248_Restore.ipsw"
```

#### Resource Allocation
Customize VM resources globally or per environment:
```toml
[vm.defaults]
cpu_count = 8        # 8 CPU cores
memory_gb = 16       # 16GB RAM
disk_size_gb = 100   # 100GB disk
```

#### Timing Adjustments
Fine-tune automation timing for reliability:
```toml
[timing]
system_settle_delay = 15    # Wait longer for slow systems
boot_wait = "300s"          # 5 minutes for IPSW boot
ssh_timeout_ipsw = "1800s"  # 30 minutes for SSH
```

#### Plugin Versions
Pin specific plugin versions for reproducibility:
```toml
[packer]
tart_version_vanilla = ">= 0.5.3"
tart_version_ipsw = ">= 1.12.0"
log_level = "0"  # Quiet builds for CI/CD
```

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