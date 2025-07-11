# Configuration Migration Guide

This guide helps existing Crostata users migrate to the new centralized configuration system introduced in Phase 1.

## What Changed

### Before (Hardcoded Values)
- VM resources, timeouts, and paths were hardcoded in `.pkr.hcl` files
- 1Password vault/item names were hardcoded in `build-with-1password.sh`
- No easy way to customize settings without editing multiple files
- Risk of accidentally committing credential changes

### After (Centralized Configuration)
- All settings moved to `config/default.toml`
- Environment variable overrides for runtime customization
- JSON schema validation for configuration correctness
- Backward compatibility maintained

## Migration Steps

### 1. No Action Required (Backward Compatible)
The system automatically falls back to original hardcoded values if the configuration file is missing. Your existing builds will continue to work without changes.

### 2. Adopt Configuration System (Recommended)

1. **Verify configuration exists:**
   ```bash
   ls -la config/default.toml config/schema.json
   ```

2. **Test configuration loading:**
   ```bash
   python3 validate-config.py --verbose
   ./build-with-1password.sh --help  # Should show "Using configuration: ..."
   ```

3. **Customize if needed:**
   ```bash
   # Copy default config for customization
   cp config/default.toml config/production.toml
   
   # Edit settings
   nano config/production.toml
   
   # Use custom config
   CONFIG_FILE="config/production.toml" ./build-with-1password.sh
   ```

### 3. Environment Variable Usage

Replace direct file editing with environment variables:

```bash
# Instead of editing vm-vanilla-custom-user.pkr.hcl:
VM_NAME_OVERRIDE="my-dev-vm" ./build-with-1password.sh

# Instead of editing build-with-1password.sh:
OP_VAULT_OVERRIDE="Development" ./build-with-1password.sh

# Chain multiple overrides:
VM_NAME_OVERRIDE="test-vm" OP_VAULT_OVERRIDE="Testing" ./build-with-1password.sh
```

## Configuration Benefits

### 1. Team Consistency
- Share `config/default.toml` in git for consistent builds
- Different environments can use different config files
- No more "works on my machine" issues

### 2. Security
- Credentials still stored securely in 1Password
- Configuration file contains no sensitive data
- Environment overrides prevent accidental commits

### 3. Maintainability
- Single source of truth for all settings
- Schema validation catches configuration errors early
- Clear documentation of all available settings

## Validation

### Configuration File Validation
```bash
# Basic validation (always available)
python3 validate-config.py

# Comprehensive validation (requires jsonschema)
pip3 install jsonschema
python3 validate-config.py --verbose
```

### Environment Validation
```bash
# The existing environment validation now supports config-aware checks
./validate-setup.sh --verbose
```

## Common Customizations

### Different VM Resources
```toml
[vm.defaults]
cpu_count = 8
memory_gb = 16
disk_size_gb = 100
```

### Different 1Password Setup
```toml
[onepassword]
vault = "Development"
item = "VM Credentials"
username_field = "vm_user"
password_field = "vm_pass"
public_key_field = "ssh_key"
```

### Performance Tuning
```toml
[timing]
system_settle_delay = 15    # Wait longer for slow systems
boot_wait = "300s"          # 5 minutes for IPSW boot

[packer]
log_level = "0"             # Quiet builds for CI/CD
```

### CI/CD Environments
```toml
[build]
colors = false              # Disable colors for logs
verbose_validation = false  # Quiet validation

[ssh]
timeout_ipsw = "1800s"      # 30 minutes for slow networks
```

## Troubleshooting

### Configuration Not Loading
- Verify file exists: `ls -la config/default.toml`
- Check syntax: `python3 validate-config.py`
- Check Python TOML library: `python3 -c "import tomllib"`

### Build Failures After Migration
- Run with verbose validation: `./validate-setup.sh --verbose`
- Check configuration validation: `python3 validate-config.py --verbose`
- Verify Packer variables are passed correctly (check build output)

### Environment Variable Issues
- Use `export` for persistent variables: `export VM_NAME_OVERRIDE="test"`
- Check variable names match exactly (case-sensitive)
- Test with simple override first: `VM_NAME_OVERRIDE="test" ./build-with-1password.sh`

## Rollback Plan

If you need to revert to the old system:

1. **Remove or rename configuration:**
   ```bash
   mv config/default.toml config/default.toml.backup
   ```

2. **System automatically falls back to hardcoded values**

3. **To restore:**
   ```bash
   mv config/default.toml.backup config/default.toml
   ```

## Support

- Configuration validation: `python3 validate-config.py --help`
- Environment validation: `./validate-setup.sh --verbose`
- Schema reference: `config/schema.json`
- Full documentation: See "Configuration Management" section in `README.md`