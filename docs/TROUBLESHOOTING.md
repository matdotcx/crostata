# VM Builder Troubleshooting Guide - Phase 3

This comprehensive troubleshooting guide provides diagnostic procedures, automated recovery tools, and solutions for common issues with the Tart VM Builder system.

## Table of Contents

1. [Quick Diagnosis](#quick-diagnosis)
2. [Automated Recovery Tools](#automated-recovery-tools)
3. [Common Issues and Solutions](#common-issues-and-solutions)
4. [Advanced Troubleshooting](#advanced-troubleshooting)
5. [Performance Issues](#performance-issues)
6. [Security Issues](#security-issues)
7. [Integration Issues](#integration-issues)
8. [Emergency Recovery](#emergency-recovery)

## Quick Diagnosis

### Initial System Check

When encountering any issues, start with this comprehensive diagnostic:

```bash
# Run complete system validation
./validate-setup.sh --full --verbose

# Check system resources
df -h
vm_stat
top -l 1

# Run automated diagnostics
./scripts/error-recovery.sh diagnostics

# Check for active alerts
./scripts/build-monitor.sh alerts
```

### Quick Status Commands

```bash
# Check all critical dependencies
for tool in op packer tart ssh-keygen jq; do
    echo -n "$tool: "
    if command -v "$tool" >/dev/null; then
        echo "✓ Available"
    else
        echo "✗ Missing"
    fi
done

# Check 1Password authentication
op account list 2>/dev/null && echo "✓ 1Password authenticated" || echo "✗ 1Password not authenticated"

# Check SSH service
sudo systemsetup -getremotelogin | grep "Remote Login: On" >/dev/null && echo "✓ SSH enabled" || echo "✗ SSH disabled"

# Check VNC service
netstat -an | grep :5900 | grep LISTEN >/dev/null && echo "✓ VNC available" || echo "✗ VNC not available"
```

## Automated Recovery Tools

### Comprehensive Error Recovery

The system includes automated recovery capabilities:

```bash
# Run comprehensive recovery (analyzes error logs and applies targeted fixes)
./scripts/error-recovery.sh comprehensive [/path/to/error.log]

# Run specific recovery modules
./scripts/error-recovery.sh ssh           # SSH service recovery
./scripts/error-recovery.sh vnc           # VNC service recovery  
./scripts/error-recovery.sh network       # Network connectivity recovery
./scripts/error-recovery.sh cleanup       # Disk space and file cleanup

# Pattern-based recovery (analyzes error patterns)
./scripts/error-recovery.sh patterns /path/to/packer-error.log
```

### Error Pattern Detection

The system can automatically detect and respond to common error patterns:

| Pattern | Description | Auto-Recovery Action |
|---------|-------------|---------------------|
| `network_timeout` | DNS or connectivity issues | DNS cache flush, network validation |
| `ssh_handshake` | SSH connection problems | SSH service restart, config validation |
| `disk_full` | Insufficient disk space | Temporary file cleanup, cache clearing |
| `vnc_connection` | VNC/Screen sharing issues | Screen sharing service restart |
| `onepassword_auth` | 1Password authentication | Authentication prompt guidance |
| `tart_permission` | Tart permission issues | Permission validation and guidance |

## Common Issues and Solutions

### 1. Build Validation Failures

#### Issue: "Environment validation failed"
**Symptoms**: Validation script reports multiple failures

**Diagnostic Steps**:
```bash
# Run detailed validation
./validate-setup.sh --verbose

# Check specific components
./validate-setup.sh --full
```

**Solutions**:
```bash
# Auto-fix common issues
./scripts/error-recovery.sh full

# Manual dependency installation
brew install hashicorp/tap/packer cirruslabs/cli/tart 1password-cli jq

# Reset configuration
cp config/default.toml.backup config/default.toml
```

#### Issue: "Packer manifest syntax errors"
**Symptoms**: Packer validation fails with syntax errors

**Diagnostic Steps**:
```bash
# Test individual manifests
packer validate vm-ipsw-1password.pkr.hcl
packer validate vm-container-1password.pkr.hcl

# Check for missing plugins
packer init vm-ipsw-1password.pkr.hcl
```

**Solutions**:
```bash
# Download required plugins
packer init .

# Update Packer
brew upgrade hashicorp/tap/packer

# Validate syntax only
packer validate -syntax-only *.pkr.hcl
```

### 2. 1Password Integration Issues

#### Issue: "1Password CLI authentication failed"
**Symptoms**: op commands fail with authentication errors

**Diagnostic Steps**:
```bash
# Check authentication status
op account list

# Check CLI version
op --version

# Test item access
op item get "Packer Automations" --vault Private
```

**Solutions**:
```bash
# Re-authenticate
op signin

# Update CLI
brew upgrade 1password-cli

# Create missing item
op item create --category=login --title="Packer Automations" --vault=Private \
  username=admin password=SecurePass123! "public key=$(cat ~/.ssh/id_rsa.pub)"
```

#### Issue: "SSH key validation failed"
**Symptoms**: SSH key format or accessibility issues

**Diagnostic Steps**:
```bash
# Check key format
op read 'op://Private/Packer Automations/public key'

# Validate key cryptographically
ssh-keygen -l -f <(op read 'op://Private/Packer Automations/public key')
```

**Solutions**:
```bash
# Generate new SSH key pair
ssh-keygen -t ed25519 -f ~/.ssh/packer_key -N ""

# Update 1Password item
op item edit "Packer Automations" --vault Private "public key=$(cat ~/.ssh/packer_key.pub)"
```

### 3. Network Connectivity Issues

#### Issue: "Network connectivity failed"
**Symptoms**: DNS resolution failures, download timeouts

**Diagnostic Steps**:
```bash
# Test basic connectivity
ping -c 3 8.8.8.8

# Test DNS resolution
nslookup google.com

# Check network interfaces
networksetup -listallhardwareports
```

**Solutions**:
```bash
# Automated network recovery
./scripts/error-recovery.sh network

# Manual DNS flush
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Check firewall settings
sudo pfctl -s info
```

### 4. SSH Service Issues

#### Issue: "SSH service validation failed"
**Symptoms**: SSH port not listening, connection refused

**Diagnostic Steps**:
```bash
# Check SSH service status
sudo launchctl list | grep ssh

# Check SSH configuration
sudo grep -E "(PermitRootLogin|PasswordAuthentication)" /etc/ssh/sshd_config

# Test SSH port
netstat -an | grep :22
```

**Solutions**:
```bash
# Automated SSH recovery
./scripts/error-recovery.sh ssh

# Manual SSH service restart
sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist

# Enable SSH via System Preferences
sudo systemsetup -setremotelogin on
```

### 5. VNC/Screen Sharing Issues

#### Issue: "VNC connection failed"
**Symptoms**: VNC port not listening, screen sharing unavailable

**Diagnostic Steps**:
```bash
# Check VNC port
netstat -an | grep :5900

# Check screen sharing status
sudo launchctl list | grep screensharing
```

**Solutions**:
```bash
# Automated VNC recovery
./scripts/error-recovery.sh vnc

# Manual screen sharing activation
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -access -on -restart -agent

# Enable via System Preferences
# System Preferences > Sharing > Screen Sharing
```

### 6. Disk Space Issues

#### Issue: "No space left on device"
**Symptoms**: Build fails due to insufficient disk space

**Diagnostic Steps**:
```bash
# Check disk usage
df -h
du -sh /tmp/* | sort -hr | head -10

# Check for large temporary files
find /tmp -size +1G -ls
```

**Solutions**:
```bash
# Automated cleanup
./scripts/error-recovery.sh cleanup

# Manual cleanup
sudo rm -rf /tmp/packer-*
sudo rm -rf /var/tmp/packer-*
brew cleanup --prune=all

# Clear system caches
sudo purge
```

## Advanced Troubleshooting

### Memory Issues

#### High Memory Usage
**Symptoms**: System becomes slow, memory pressure warnings

**Diagnostic Steps**:
```bash
# Check memory usage
vm_stat
top -o mem

# Check for memory leaks
sudo leaks -nocontext -quiet $(pgrep packer) 2>/dev/null
```

**Solutions**:
```bash
# Free memory caches
sudo purge

# Kill memory-intensive processes
pkill -f "packer.*build"

# Increase virtual memory (if needed)
sudo sysctl -w vm.swappiness=10
```

#### Memory Pressure Alerts
**Symptoms**: System reports memory pressure during builds

**Solutions**:
```bash
# Monitor memory during builds
./scripts/build-monitor.sh monitor 1800  # 30 minutes

# Optimize memory settings
export PACKER_MAX_PROCS=2  # Reduce parallelism
export TMPDIR=/path/to/fast/storage
```

### CPU Issues

#### High CPU Usage
**Symptoms**: System becomes unresponsive, high load average

**Diagnostic Steps**:
```bash
# Check CPU usage
top -o cpu
ps aux --sort=-%cpu | head -10

# Check system load
uptime
```

**Solutions**:
```bash
# Limit CPU usage
export PACKER_MAX_PROCS=1
nice -n 10 ./build-with-1password.sh

# Check for runaway processes
pkill -f "tart.*"
pkill -f "packer.*"
```

### Build Performance Issues

#### Slow Build Times
**Symptoms**: Builds take significantly longer than expected

**Diagnostic Steps**:
```bash
# Compare with baseline
./scripts/build-monitor.sh baseline

# Performance profiling
./validate-setup.sh --performance

# Check resource bottlenecks
./scripts/build-monitor.sh monitor 300
```

**Solutions**:
```bash
# Optimize build environment
export PACKER_TMP_DIR="/path/to/fast/storage"
export PACKER_CACHE_DIR="/path/to/cache"

# Use SSD for temporary files
sudo diskutil info / | grep "Solid State"

# Close unnecessary applications
killall -9 "Background App Name"
```

## Performance Issues

### Build Performance Optimization

#### Resource Allocation
```bash
# Check system specifications
system_profiler SPHardwareDataType | grep -E "(Memory|Processor)"

# Optimize for available resources
if [ $(sysctl -n hw.ncpu) -ge 8 ]; then
    export PACKER_MAX_PROCS=4
else
    export PACKER_MAX_PROCS=2
fi
```

#### Storage Optimization
```bash
# Use fastest available storage
if [ -d "/Volumes/FastSSD" ]; then
    export TMPDIR="/Volumes/FastSSD/tmp"
    export PACKER_TMP_DIR="/Volumes/FastSSD/packer"
fi

# Clean up before builds
./scripts/security-hardening.sh optimize
```

### Monitoring Performance

#### Real-time Monitoring
```bash
# Start comprehensive monitoring
./scripts/build-monitor.sh start "performance_test" "test-manifest"

# Monitor specific metrics
./scripts/build-monitor.sh monitor 3600  # 1 hour
```

#### Performance Analysis
```bash
# Generate performance report
./scripts/build-monitor.sh report

# Compare with baseline
cat /tmp/vm-builder-monitoring/performance-baseline.json

# Analyze trends
jq '.performance_trends' /tmp/vm-builder-monitoring/metrics.json
```

## Security Issues

### Permission Issues

#### File Permission Problems
**Symptoms**: Scripts fail to execute, permission denied errors

**Solutions**:
```bash
# Run security hardening
./scripts/security-hardening.sh permissions

# Manual permission fixes
chmod 755 *.sh scripts/*.sh
chmod 644 config/*.toml
```

### Security Validation

#### Security Audit
```bash
# Run comprehensive security check
./scripts/security-hardening.sh harden comprehensive

# Check for security issues
./scripts/security-hardening.sh secrets
./scripts/security-hardening.sh integrity
```

#### 1Password Security
```bash
# Validate 1Password security
./scripts/security-hardening.sh 1password

# Check for hardcoded secrets
./scripts/security-hardening.sh secrets
```

## Integration Issues

### Packer Integration

#### Plugin Issues
**Symptoms**: Packer fails to load plugins

**Solutions**:
```bash
# Initialize plugins
packer init .

# Update plugins
rm -rf ~/.config/packer/plugins
packer init .

# Manual plugin installation
packer plugins install github.com/cirruslabs/tart latest
```

#### Tart Integration
**Symptoms**: Tart commands fail, VM creation errors

**Solutions**:
```bash
# Check Tart installation
tart --version
tart list

# Update Tart
brew upgrade cirruslabs/cli/tart

# Check permissions
./scripts/security-hardening.sh harden
```

### Testing Integration

#### Test Framework Issues
**Symptoms**: Tests fail to run or report incorrect results

**Solutions**:
```bash
# Run test suite
./scripts/test-framework.sh run all

# Debug specific test categories
./scripts/test-framework.sh run unit
./scripts/test-framework.sh run integration

# Check test environment
./scripts/test-framework.sh init
```

## Emergency Recovery

### Complete System Recovery

If the entire VM builder system is non-functional:

#### Step 1: System Assessment
```bash
# Check basic system health
uptime
df -h
free -h  # or vm_stat on macOS

# Check critical dependencies
which packer tart op jq
```

#### Step 2: Dependency Recovery
```bash
# Reinstall all dependencies
brew update
brew reinstall hashicorp/tap/packer
brew reinstall cirruslabs/cli/tart
brew reinstall 1password-cli
brew reinstall jq

# Verify installations
./validate-setup.sh --verbose
```

#### Step 3: Configuration Recovery
```bash
# Reset configuration to defaults
cp config/default.toml.backup config/default.toml

# Validate configuration
python3 validate-config.py
```

#### Step 4: Full System Recovery
```bash
# Run comprehensive recovery
./scripts/error-recovery.sh comprehensive

# Run security hardening
./scripts/security-hardening.sh harden comprehensive

# Validate complete system
./validate-setup.sh --full --performance
```

### Data Recovery

#### Log Recovery
```bash
# Archive current logs before cleanup
tar -czf "emergency-logs-$(date +%Y%m%d).tar.gz" /tmp/vm-builder-*

# Restore from backup (if available)
# cp /path/to/backup/logs/* /tmp/vm-builder-*/
```

#### Configuration Recovery
```bash
# Restore from Git (if tracked)
git checkout HEAD -- config/

# Regenerate default configuration
python3 -c "
import toml
config = {
    'build': {'timeout_minutes': 30},
    'vm': {'memory_gb': 4, 'cpu_cores': 2},
    'paths': {'temp_dir': '/tmp', 'cache_dir': '~/.cache'}
}
with open('config/default.toml', 'w') as f:
    toml.dump(config, f)
"
```

## Escalation Procedures

### When to Escalate

Escalate to higher-level support when:

1. **Automated recovery fails** after multiple attempts
2. **Hardware issues** are suspected (overheating, disk failure)
3. **Security breaches** are detected
4. **System corruption** prevents basic operations
5. **Performance degradation** persists despite optimization

### Information to Collect Before Escalation

```bash
# Collect system information
./scripts/error-recovery.sh diagnostics > system-info.json

# Collect performance data
./scripts/build-monitor.sh report > performance-report.md

# Collect security audit
./scripts/security-hardening.sh report > security-audit.md

# Collect test results
./scripts/test-framework.sh run all > test-results.txt

# Collect logs
tar -czf "support-logs-$(date +%Y%m%d).tar.gz" \
  /tmp/vm-builder-* \
  packer-*.log \
  system-info.json \
  performance-report.md \
  security-audit.md \
  test-results.txt
```

### Support Contacts

- **System Administrator**: Review hardware and OS-level issues
- **Security Team**: For security-related incidents
- **Development Team**: For code-related issues
- **Infrastructure Team**: For network and resource issues

## Appendix

### Useful Commands Reference

| Task | Command |
|------|---------|
| Quick validation | `./validate-setup.sh --silent` |
| Full diagnosis | `./validate-setup.sh --full --verbose` |
| Error recovery | `./scripts/error-recovery.sh comprehensive` |
| Performance monitoring | `./scripts/build-monitor.sh monitor 300` |
| Security hardening | `./scripts/security-hardening.sh harden` |
| Test system | `./scripts/test-framework.sh run all` |
| Clean system | `./scripts/error-recovery.sh cleanup` |

### Log File Locations

- **Validation logs**: `/tmp/vm-builder-validation-*.log`
- **Recovery logs**: `/tmp/vm-builder-recovery/diagnostic-*.log`
- **Monitoring logs**: `/tmp/vm-builder-monitoring/build-session-*.log`
- **Security logs**: `/tmp/vm-builder-security/security-audit-*.log`
- **Test logs**: `/tmp/vm-builder-tests/test-framework.log`
- **Packer logs**: `./packer-*.log`

### Emergency Contact Procedures

In case of critical system failure:

1. **Stop all running builds**: `pkill -f packer`
2. **Collect diagnostic data**: Use commands above
3. **Document the issue**: Include steps to reproduce
4. **Contact appropriate support**: Based on issue category
5. **Preserve system state**: Avoid making changes until instructed