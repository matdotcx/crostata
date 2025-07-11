# VM Builder Operations Guide - Phase 3

This document provides comprehensive operational procedures, troubleshooting guides, and runbooks for the Tart VM Builder system.

## Table of Contents

1. [Quick Start Operations](#quick-start-operations)
2. [System Monitoring](#system-monitoring)
3. [Troubleshooting Runbooks](#troubleshooting-runbooks)
4. [Performance Optimization](#performance-optimization)
5. [Security Operations](#security-operations)
6. [Maintenance Procedures](#maintenance-procedures)
7. [Emergency Procedures](#emergency-procedures)
8. [Log Analysis](#log-analysis)

## Quick Start Operations

### Pre-Flight Checklist

Before starting any VM build operation, run through this checklist:

```bash
# 1. System validation (comprehensive)
./validate-setup.sh --full --verbose

# 2. Initialize monitoring
./scripts/build-monitor.sh init

# 3. Run system tests
./scripts/test-framework.sh run unit

# 4. Check available resources
df -h .
free -h  # or vm_stat on macOS
```

### Standard Build Workflow

```bash
# 1. Start monitoring session
./scripts/build-monitor.sh start "ipsw" "vm-ipsw-1password.pkr.hcl"

# 2. Run build with error recovery
./build-with-1password.sh

# 3. If build fails, run recovery
./scripts/error-recovery.sh comprehensive /path/to/error.log

# 4. Complete monitoring
./scripts/build-monitor.sh complete success
```

### Post-Build Operations

```bash
# 1. Generate reports
./scripts/build-monitor.sh report
./scripts/test-framework.sh run integration

# 2. Clean up temporary files
./scripts/error-recovery.sh cleanup

# 3. Archive logs (optional)
tar -czf "build-logs-$(date +%Y%m%d).tar.gz" /tmp/vm-builder-*
```

## System Monitoring

### Real-Time Monitoring

The VM Builder includes comprehensive monitoring capabilities:

#### Performance Metrics
- **CPU Usage**: Tracked during builds with alerts for high usage
- **Memory Usage**: Peak memory tracking with pressure monitoring
- **Disk Usage**: Space monitoring with automatic cleanup
- **Network Activity**: Download tracking and latency monitoring

#### Monitoring Commands

```bash
# Start continuous monitoring
./scripts/build-monitor.sh monitor 3600  # Monitor for 1 hour

# Check performance alerts
./scripts/build-monitor.sh alerts

# Generate performance baseline
./scripts/build-monitor.sh baseline

# View current metrics
cat /tmp/vm-builder-monitoring/metrics.json | jq '.global_metrics'
```

### Log Locations

| Component | Log Location | Description |
|-----------|-------------|-------------|
| Validation | `/tmp/vm-builder-validation-*.log` | Environment validation logs |
| Error Recovery | `/tmp/vm-builder-recovery/diagnostic-*.log` | Recovery system logs |
| Monitoring | `/tmp/vm-builder-monitoring/build-session-*.log` | Build monitoring logs |
| Tests | `/tmp/vm-builder-tests/test-framework.log` | Test execution logs |
| Packer | `./packer-*.log` | Packer build logs |

### Performance Baselines

The system automatically creates performance baselines based on your hardware:

```bash
# View current baseline
cat /tmp/vm-builder-monitoring/performance-baseline.json

# Recreate baseline (after hardware changes)
./scripts/build-monitor.sh baseline
```

## Troubleshooting Runbooks

### Build Failure Recovery

When a build fails, follow this procedure:

#### 1. Immediate Assessment
```bash
# Check system health
./scripts/error-recovery.sh diagnostics

# Analyze error patterns
./scripts/error-recovery.sh patterns /path/to/packer-error.log

# Run comprehensive recovery
./scripts/error-recovery.sh comprehensive /path/to/packer-error.log
```

#### 2. Common Issues and Solutions

##### Issue: Network Connectivity Problems
**Symptoms**: DNS resolution failures, download timeouts, network unreachable errors

**Solution**:
```bash
# Run network recovery
./scripts/error-recovery.sh network

# Manual steps if automated recovery fails:
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
ping -c 3 8.8.8.8
```

##### Issue: SSH Connection Failures
**Symptoms**: SSH handshake errors, connection refused, authentication failures

**Solution**:
```bash
# Run SSH recovery
./scripts/error-recovery.sh ssh

# Manual verification:
sudo systemsetup -getremotelogin
netstat -an | grep :22
```

##### Issue: VNC/Screen Sharing Problems
**Symptoms**: VNC connection failed, screen sharing unavailable

**Solution**:
```bash
# Run VNC recovery
./scripts/error-recovery.sh vnc

# Manual configuration:
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -restart -agent
```

##### Issue: Disk Space Exhaustion
**Symptoms**: "No space left on device", disk usage >95%

**Solution**:
```bash
# Run cleanup
./scripts/error-recovery.sh cleanup

# Check disk usage
df -h /
du -sh /tmp/packer-* /var/tmp/packer-*

# Manual cleanup if needed:
find /tmp -name "packer-*" -type d -mtime +1 -exec rm -rf {} \;
```

##### Issue: 1Password Authentication
**Symptoms**: 1Password CLI authentication errors, item not found

**Solution**:
```bash
# Check authentication status
op account list

# Re-authenticate if needed
op signin

# Verify item exists
op item get "Packer Automations" --vault Private
```

### Performance Issues

#### Slow Build Times
1. **Check system resources**:
   ```bash
   top -l 1 | head -20
   vm_stat
   df -h
   ```

2. **Compare with baseline**:
   ```bash
   ./scripts/build-monitor.sh baseline
   ```

3. **Optimize system**:
   ```bash
   # Close unnecessary applications
   # Free up disk space
   # Check for background processes
   ps aux | grep -E "(backup|sync|indexing)"
   ```

#### High Resource Usage
1. **Monitor in real-time**:
   ```bash
   ./scripts/build-monitor.sh monitor 300  # 5 minutes
   ```

2. **Check for resource leaks**:
   ```bash
   lsof | grep packer
   ps aux | grep tart
   ```

## Performance Optimization

### System Configuration

#### Recommended Settings
```bash
# Increase file descriptor limits
ulimit -n 4096

# Optimize network settings
sudo sysctl -w net.inet.tcp.win_scale_factor=8

# Set optimal temp directory
export TMPDIR=/tmp
```

#### Build Optimization
```bash
# Use faster temporary storage if available
export PACKER_TMP_DIR="/path/to/fast/storage"

# Parallel builds (if supported)
export PACKER_MAX_PROCS=4

# Optimize network timeouts
export PACKER_HTTP_TIMEOUT=30s
```

### Resource Management

#### Memory Management
- **Minimum**: 8GB RAM
- **Recommended**: 16GB+ RAM
- **Monitoring**: Watch for memory pressure warnings

#### Disk Management
- **Minimum**: 50GB free space
- **Recommended**: 100GB+ free space
- **Monitoring**: Automated cleanup at 85% usage

#### CPU Management
- **Minimum**: 4 cores
- **Recommended**: 8+ cores
- **Monitoring**: Alert at 85% sustained usage

## Security Operations

### Security Validation

```bash
# Run security tests
./scripts/test-framework.sh run security

# Check for hardcoded secrets
grep -r -E "(password|secret|key).*=" . --exclude-dir=.git

# Validate file permissions
find . -name "*.sh" -exec ls -la {} \;
```

### 1Password Security

#### Best Practices
- Use dedicated vault for Packer items
- Rotate credentials regularly
- Monitor access logs
- Use service accounts where possible

#### Security Checklist
```bash
# Verify 1Password CLI version
op --version

# Check authentication status
op account list

# Validate item accessibility
op item get "Packer Automations" --vault Private --format json
```

### System Security

#### SSH Configuration
```bash
# Check SSH configuration
sudo cat /etc/ssh/sshd_config | grep -E "(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)"

# Verify SSH service status
sudo launchctl list | grep ssh
```

#### File Permissions
```bash
# Set correct permissions
chmod 755 ./validate-setup.sh
chmod 755 ./scripts/*.sh
chmod 644 ./config/*.toml
```

## Maintenance Procedures

### Daily Maintenance

```bash
#!/bin/bash
# Daily maintenance script

# Clean old logs
find /tmp/vm-builder-* -name "*.log" -mtime +7 -delete

# Check system health
./validate-setup.sh --silent

# Update performance metrics
./scripts/build-monitor.sh baseline
```

### Weekly Maintenance

```bash
#!/bin/bash
# Weekly maintenance script

# Run comprehensive tests
./scripts/test-framework.sh run all

# Clean up old monitoring data
find /tmp/vm-builder-monitoring -name "*.json" -mtime +30 -delete

# Archive old logs
tar -czf "logs-archive-$(date +%Y%m%d).tar.gz" /tmp/vm-builder-*/*.log
```

### Monthly Maintenance

```bash
#!/bin/bash
# Monthly maintenance script

# Update dependencies
brew update && brew upgrade packer tart 1password-cli jq

# Recreate performance baseline
./scripts/build-monitor.sh baseline

# Full system validation
./validate-setup.sh --full --performance

# Security audit
./scripts/test-framework.sh run security
```

## Emergency Procedures

### Complete System Recovery

If the VM builder system is completely non-functional:

#### 1. System Assessment
```bash
# Check basic system health
uptime
df -h
free -h  # or vm_stat on macOS
ps aux | head -20
```

#### 2. Dependency Recovery
```bash
# Reinstall critical dependencies
brew reinstall packer
brew reinstall cirruslabs/cli/tart
brew reinstall 1password-cli
brew reinstall jq
```

#### 3. Configuration Recovery
```bash
# Reset to default configuration
cp config/default.toml.backup config/default.toml

# Validate configuration
python3 validate-config.py
```

#### 4. Full System Recovery
```bash
# Run comprehensive recovery
./scripts/error-recovery.sh comprehensive

# Reinitialize monitoring
./scripts/build-monitor.sh init

# Validate system
./validate-setup.sh --full
```

### Escalation Procedures

#### Level 1: Automated Recovery
- Run error recovery scripts
- Check monitoring logs
- Apply standard troubleshooting

#### Level 2: Manual Intervention
- Review system logs
- Check hardware status
- Manual configuration fixes

#### Level 3: Expert Support
- Contact system administrator
- Review architecture documentation
- Consider system rebuild

## Log Analysis

### Log Parsing Commands

```bash
# Parse validation logs
grep -E "(ERROR|FAIL)" /tmp/vm-builder-validation-*.log

# Parse monitoring logs
jq '.[] | select(.level == "ERROR")' /tmp/vm-builder-monitoring/build-session-*.log

# Parse test logs
grep -E "(FAIL|ERROR)" /tmp/vm-builder-tests/test-framework.log

# Parse Packer logs
grep -E "(Error|Failed)" packer-*.log
```

### Performance Analysis

```bash
# Analyze build times
jq '.build_sessions | to_entries[] | {session: .key, duration: .value.total_duration_seconds}' /tmp/vm-builder-monitoring/metrics.json

# Check resource usage trends
jq '.performance_trends' /tmp/vm-builder-monitoring/metrics.json

# Alert analysis
jq '.alerts.alert_history | .[] | select(.timestamp > "2024-01-01")' /tmp/vm-builder-monitoring/metrics.json
```

### Error Pattern Analysis

```bash
# Common error patterns
./scripts/error-recovery.sh patterns /path/to/error.log

# Failure frequency analysis
grep -c "FAILED" /tmp/vm-builder-*/*.log

# Performance degradation detection
./scripts/build-monitor.sh alerts
```

## Appendix

### Quick Reference Commands

| Task | Command |
|------|---------|
| System Validation | `./validate-setup.sh --full` |
| Start Monitoring | `./scripts/build-monitor.sh start TYPE MANIFEST` |
| Error Recovery | `./scripts/error-recovery.sh comprehensive` |
| Run Tests | `./scripts/test-framework.sh run all` |
| Check Alerts | `./scripts/build-monitor.sh alerts` |
| Generate Report | `./scripts/build-monitor.sh report` |
| System Cleanup | `./scripts/error-recovery.sh cleanup` |

### Contact Information

- **Documentation**: See README.md and PHASE2_IMPROVEMENTS.md
- **Configuration**: config/default.toml
- **Logs**: /tmp/vm-builder-* directories
- **Source Code**: Current directory structure

### Version Information

- **Operations Guide Version**: 3.0
- **Compatible with**: VM Builder Phase 3
- **Last Updated**: $(date)
- **Requires**: macOS 13.0+, Apple Silicon