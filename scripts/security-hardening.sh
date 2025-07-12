#!/bin/bash
# VM Builder Security Hardening and Resource Management - Phase 3
# Implements security best practices and resource optimization

set -eo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Global configuration
SECURITY_LOG_DIR="/tmp/vm-builder-security"
SECURITY_LOG_FILE="$SECURITY_LOG_DIR/security-audit-$(date +%Y%m%d-%H%M%S).log"
RESOURCE_LOG_FILE="$SECURITY_LOG_DIR/resource-optimization-$(date +%Y%m%d-%H%M%S).log"
SESSION_ID=$(date +%s%N | cut -c1-13)

# Security configuration
MAX_FILE_PERMISSIONS="755"
MAX_CONFIG_PERMISSIONS="644"
REQUIRED_SSH_SETTINGS="PubkeyAuthentication yes"
FORBIDDEN_SSH_SETTINGS="PermitEmptyPasswords yes"
MAX_LOG_AGE_DAYS="30"
MAX_TEMP_FILE_AGE_DAYS="7"

# Resource limits
MAX_DISK_USAGE_PERCENT="85"
MAX_MEMORY_USAGE_PERCENT="90"
MAX_CPU_USAGE_PERCENT="95"
MIN_FREE_SPACE_GB="10"
MAX_LOG_SIZE_MB="100"

# Initialize security system
init_security_system() {
    mkdir -p "$SECURITY_LOG_DIR"
    
    log_security "INFO" "Security hardening system initialized for session $SESSION_ID"
}

# Security logging
log_security() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Console output with colors
    case "$level" in
        ERROR) echo -e "${RED}[SECURITY-ERROR]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[SECURITY-WARN]${NC} $message" ;;
        INFO) echo -e "${BLUE}[SECURITY-INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SECURITY-SUCCESS]${NC} $message" ;;
        CRITICAL) echo -e "${RED}[SECURITY-CRITICAL]${NC} $message" ;;
    esac
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$SECURITY_LOG_FILE"
}

# File permission hardening
harden_file_permissions() {
    log_security "INFO" "Starting file permission hardening..."
    
    local security_issues=0
    
    # Check and fix script permissions
    local scripts=(
        "./validate-setup.sh"
        "./build-with-1password.sh"
        "./scripts/error-recovery.sh"
        "./scripts/build-monitor.sh"
        "./scripts/test-framework.sh"
        "./scripts/security-hardening.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            local current_perms=$(stat -f "%A" "$script")
            
            if [ "$current_perms" -gt "$MAX_FILE_PERMISSIONS" ]; then
                log_security "WARN" "Script $script has overly permissive permissions: $current_perms"
                chmod 755 "$script"
                log_security "INFO" "Fixed permissions for $script: 755"
            else
                log_security "SUCCESS" "Script $script has appropriate permissions: $current_perms"
            fi
        else
            log_security "WARN" "Script not found: $script"
        fi
    done
    
    # Check configuration file permissions
    local config_files=(
        "./config/default.toml"
        "./config/schema.json"
    )
    
    for config in "${config_files[@]}"; do
        if [ -f "$config" ]; then
            local current_perms=$(stat -f "%A" "$config")
            
            if [ "$current_perms" -gt "$MAX_CONFIG_PERMISSIONS" ]; then
                log_security "WARN" "Config file $config has overly permissive permissions: $current_perms"
                chmod 644 "$config"
                log_security "INFO" "Fixed permissions for $config: 644"
                security_issues=$((security_issues + 1))
            else
                log_security "SUCCESS" "Config file $config has appropriate permissions: $current_perms"
            fi
        fi
    done
    
    # Check for world-writable files
    local world_writable=$(find . -type f -perm -002 2>/dev/null | grep -v ".git" | head -10)
    if [ -n "$world_writable" ]; then
        log_security "CRITICAL" "Found world-writable files:"
        echo "$world_writable" | while read -r file; do
            log_security "CRITICAL" "  - $file"
            chmod o-w "$file"
            log_security "INFO" "Removed world-write permission from $file"
        done
        security_issues=$((security_issues + 1))
    fi
    
    log_security "INFO" "File permission hardening completed with $security_issues issues fixed"
    return $security_issues
}

# SSH configuration hardening
harden_ssh_configuration() {
    log_security "INFO" "Checking SSH configuration security..."
    
    local ssh_config="/etc/ssh/sshd_config"
    local security_issues=0
    
    if [ -f "$ssh_config" ]; then
        # Check for secure settings
        if ! grep -q "PubkeyAuthentication yes" "$ssh_config"; then
            log_security "WARN" "SSH PubkeyAuthentication not explicitly enabled"
            security_issues=$((security_issues + 1))
        fi
        
        if grep -q "PermitRootLogin yes" "$ssh_config"; then
            log_security "CRITICAL" "SSH PermitRootLogin is enabled - security risk!"
            security_issues=$((security_issues + 1))
        fi
        
        if grep -q "PasswordAuthentication yes" "$ssh_config"; then
            log_security "WARN" "SSH PasswordAuthentication is enabled - consider key-only auth"
            security_issues=$((security_issues + 1))
        fi
        
        if grep -q "PermitEmptyPasswords yes" "$ssh_config"; then
            log_security "CRITICAL" "SSH PermitEmptyPasswords is enabled - critical security risk!"
            security_issues=$((security_issues + 1))
        fi
        
        # Check SSH service status
        if sudo launchctl list | grep -q ssh; then
            log_security "INFO" "SSH service is running"
        else
            log_security "WARN" "SSH service is not running"
        fi
        
    else
        log_security "WARN" "SSH configuration file not found"
        security_issues=$((security_issues + 1))
    fi
    
    log_security "INFO" "SSH configuration check completed with $security_issues potential issues"
    return $security_issues
}

# 1Password security validation
validate_1password_security() {
    log_security "INFO" "Validating 1Password security configuration..."
    
    local security_issues=0
    
    # Check 1Password CLI authentication
    if ! op account list >/dev/null 2>&1; then
        log_security "CRITICAL" "1Password CLI not authenticated - security risk for credentials"
        security_issues=$((security_issues + 1))
        return $security_issues
    fi
    
    # Check item accessibility and structure
    if op item get "Packer Automations" --vault Private >/dev/null 2>&1; then
        log_security "SUCCESS" "1Password item 'Packer Automations' is accessible"
        
        # Check for proper field structure
        local item_json=$(op item get "Packer Automations" --vault Private --format json)
        
        # Validate required fields exist
        local required_fields=("username" "password" "public key")
        for field in "${required_fields[@]}"; do
            if echo "$item_json" | jq -e ".fields[] | select(.label == \"$field\")" >/dev/null 2>&1; then
                log_security "SUCCESS" "1Password item has required field: $field"
            else
                log_security "CRITICAL" "1Password item missing required field: $field"
                security_issues=$((security_issues + 1))
            fi
        done
        
        # Check SSH key format if present
        if echo "$item_json" | jq -e '.fields[] | select(.label == "public key")' >/dev/null 2>&1; then
            local public_key=$(op read 'op://Private/Packer Automations/public key' 2>/dev/null || echo "")
            if [ -n "$public_key" ]; then
                if echo "$public_key" | grep -E '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-)' >/dev/null; then
                    log_security "SUCCESS" "SSH public key format appears valid"
                else
                    log_security "CRITICAL" "SSH public key format is invalid"
                    security_issues=$((security_issues + 1))
                fi
            fi
        fi
        
    else
        log_security "CRITICAL" "1Password item 'Packer Automations' not accessible"
        security_issues=$((security_issues + 1))
    fi
    
    log_security "INFO" "1Password security validation completed with $security_issues issues"
    return $security_issues
}

# Secret scanning
scan_for_secrets() {
    log_security "INFO" "Scanning for potential hardcoded secrets..."
    
    local secrets_found=0
    local patterns=(
        "password\s*=\s*['\"][^'\"]{3,}['\"]"
        "secret\s*=\s*['\"][^'\"]{3,}['\"]"
        "key\s*=\s*['\"][^'\"]{8,}['\"]"
        "token\s*=\s*['\"][^'\"]{8,}['\"]"
        "api[_-]?key\s*=\s*['\"][^'\"]{8,}['\"]"
    )
    
    local files_to_scan=(
        "*.sh"
        "*.py"
        "*.toml"
        "*.json"
        "*.pkr.hcl"
    )
    
    for file_pattern in "${files_to_scan[@]}"; do
        for file in $file_pattern; do
            if [ -f "$file" ]; then
                for pattern in "${patterns[@]}"; do
                    if grep -E "$pattern" "$file" 2>/dev/null | grep -v -E "(example|template|placeholder|default|TODO)" | grep -q .; then
                        log_security "CRITICAL" "Potential hardcoded secret found in $file"
                        secrets_found=$((secrets_found + 1))
                    fi
                done
            fi
        done
    done
    
    if [ $secrets_found -eq 0 ]; then
        log_security "SUCCESS" "No hardcoded secrets detected"
    else
        log_security "CRITICAL" "Found $secrets_found potential hardcoded secrets"
    fi
    
    return $secrets_found
}

# Network security validation
validate_network_security() {
    log_security "INFO" "Validating network security configuration..."
    
    local security_issues=0
    
    # Check for open ports that shouldn't be
    local suspicious_ports=("21" "23" "135" "139" "445" "1433" "3389")
    
    for port in "${suspicious_ports[@]}"; do
        # macOS-compatible port checking with better pattern matching
        if netstat -an | grep -E "(tcp|tcp4|tcp6).*[.:]${port}[[:space:]].*LISTEN" >/dev/null 2>&1; then
            log_security "WARN" "Potentially insecure service listening on port $port"
            security_issues=$((security_issues + 1))
        fi
    done
    
    # Check firewall status (if available)
    if command -v pfctl >/dev/null 2>&1; then
        if sudo pfctl -s info 2>/dev/null | grep -q "Status: Enabled"; then
            log_security "SUCCESS" "Firewall (pfctl) is enabled"
        else
            log_security "WARN" "Firewall (pfctl) may not be enabled"
            security_issues=$((security_issues + 1))
        fi
    fi
    
    # Check DNS configuration (macOS native with fallback)
    if command -v scutil >/dev/null 2>&1; then
        local dns_servers=$(scutil --dns 2>/dev/null | grep nameserver | head -3 | awk '{print $3}')
        if [ -n "$dns_servers" ]; then
            log_security "INFO" "DNS servers configured: $(echo "$dns_servers" | tr '\n' ' ')"
        else
            log_security "WARN" "No DNS servers detected via scutil"
            security_issues=$((security_issues + 1))
        fi
    else
        log_security "WARN" "scutil not available for DNS configuration check"
        security_issues=$((security_issues + 1))
    fi
    
    log_security "INFO" "Network security validation completed with $security_issues issues"
    return $security_issues
}

# Resource management and optimization
optimize_system_resources() {
    log_security "INFO" "Starting system resource optimization..."
    
    local optimizations_applied=0
    
    # Clean up old temporary files
    log_security "INFO" "Cleaning up old temporary files..."
    
    local temp_dirs=(
        "/tmp/packer-*"
        "/tmp/vm-builder-*"
        "/var/tmp/packer-*"
    )
    
    for temp_pattern in "${temp_dirs[@]}"; do
        find $(dirname "$temp_pattern") -name "$(basename "$temp_pattern")" -type d -mtime +$MAX_TEMP_FILE_AGE_DAYS -exec rm -rf {} \; 2>/dev/null || true
    done
    
    # Clean up old log files
    log_security "INFO" "Cleaning up old log files..."
    find /tmp -name "*.log" -mtime +$MAX_LOG_AGE_DAYS -delete 2>/dev/null || true
    optimizations_applied=$((optimizations_applied + 1))
    
    # Optimize memory usage
    log_security "INFO" "Checking memory optimization opportunities..."
    
    local memory_pressure=$(vm_stat | grep "Pages purgeable" | awk '{print $3}' | sed 's/\.//' || echo "0")
    if [ "$memory_pressure" -gt 1000000 ]; then
        log_security "INFO" "High memory pressure detected, suggesting memory cleanup"
        if command -v purge >/dev/null 2>&1; then
            sudo purge 2>/dev/null || true
            log_security "INFO" "Memory purge completed"
            optimizations_applied=$((optimizations_applied + 1))
        fi
    fi
    
    # Disk space optimization
    log_security "INFO" "Checking disk space optimization opportunities..."
    
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt "$MAX_DISK_USAGE_PERCENT" ]; then
        log_security "WARN" "Disk usage is ${disk_usage}%, running cleanup..."
        
        # Clean system caches (safely)
        rm -rf ~/.cache/* 2>/dev/null || true
        
        # Clean Homebrew cache
        if command -v brew >/dev/null 2>&1; then
            brew cleanup --prune=all 2>/dev/null || true
            optimizations_applied=$((optimizations_applied + 1))
        fi
        
        # Clean Packer cache
        rm -rf ~/.cache/packer/* 2>/dev/null || true
        
        optimizations_applied=$((optimizations_applied + 1))
    fi
    
    # Process optimization
    log_security "INFO" "Checking for resource-intensive processes..."
    
    local high_cpu_processes=$(ps aux | sort -rn -k 3 | head -5 | tail -4 | awk '$3 > 80 {print $2, $11}' | wc -l)
    if [ "$high_cpu_processes" -gt 0 ]; then
        log_security "WARN" "Found $high_cpu_processes high CPU usage processes"
        ps aux | sort -rn -k 3 | head -5 | tail -4 | awk '$3 > 80 {print "PID " $2 ": " $11 " (" $3 "% CPU)"}' | while read -r line; do
            log_security "WARN" "High CPU: $line"
        done
    fi
    
    log_security "INFO" "Resource optimization completed with $optimizations_applied optimizations applied"
    return 0
}

# System integrity validation
validate_system_integrity() {
    log_security "INFO" "Validating system integrity..."
    
    local integrity_issues=0
    
    # Check critical files exist and are not tampered with
    local critical_files=(
        "./validate-setup.sh"
        "./build-with-1password.sh"
        "./config/default.toml"
    )
    
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            # Check if file is readable and has content
            if [ -r "$file" ] && [ -s "$file" ]; then
                log_security "SUCCESS" "Critical file $file is accessible and has content"
            else
                log_security "CRITICAL" "Critical file $file exists but may be corrupted"
                integrity_issues=$((integrity_issues + 1))
            fi
            
            # Check for suspicious modifications (very basic)
            if grep -q "curl.*|.*sh" "$file" 2>/dev/null; then
                log_security "CRITICAL" "Suspicious content detected in $file (potential malware)"
                integrity_issues=$((integrity_issues + 1))
            fi
        else
            log_security "CRITICAL" "Critical file missing: $file"
            integrity_issues=$((integrity_issues + 1))
        fi
    done
    
    # Check for suspicious processes
    local suspicious_patterns=("nc -l" "wget.*|.*sh" "curl.*|.*bash")
    for pattern in "${suspicious_patterns[@]}"; do
        if ps aux | grep -E "$pattern" | grep -v grep >/dev/null; then
            log_security "CRITICAL" "Suspicious process detected: $pattern"
            integrity_issues=$((integrity_issues + 1))
        fi
    done
    
    # Check system load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_avg > 10" | bc -l 2>/dev/null || echo "0") )); then
        log_security "WARN" "High system load detected: $load_avg"
        integrity_issues=$((integrity_issues + 1))
    fi
    
    log_security "INFO" "System integrity validation completed with $integrity_issues issues"
    return $integrity_issues
}

# Generate security audit report
generate_security_report() {
    local report_file="$SECURITY_LOG_DIR/security-audit-report-$(date +%Y%m%d-%H%M%S).md"
    
    {
        echo "# VM Builder Security Audit Report"
        echo ""
        echo "**Session ID:** $SESSION_ID"
        echo "**Date:** $(date)"
        echo "**System:** $(uname -a)"
        echo ""
        
        echo "## Security Checks Performed"
        echo ""
        echo "- File permission hardening"
        echo "- SSH configuration validation"
        echo "- 1Password security validation"
        echo "- Secret scanning"
        echo "- Network security validation"
        echo "- System integrity validation"
        echo ""
        
        echo "## Resource Optimization"
        echo ""
        echo "- Temporary file cleanup"
        echo "- Log file management"
        echo "- Memory optimization"
        echo "- Disk space optimization"
        echo "- Process monitoring"
        echo ""
        
        echo "## System Status"
        echo ""
        echo "- **Disk Usage:** $(df -h / | tail -1 | awk '{print $5}')"
        echo "- **Memory Usage:** $(vm_stat | grep -E 'free|active' | head -2 | awk '{sum+=$3} END {print int(sum*4096/1024/1024) "MB"}')"
        echo "- **Load Average:** $(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')"
        echo "- **Uptime:** $(uptime | awk '{print $3,$4}' | sed 's/,//')"
        echo ""
        
        echo "## Recommendations"
        echo ""
        echo "- Review security log for any critical issues"
        echo "- Ensure 1Password authentication is maintained"
        echo "- Regularly update system dependencies"
        echo "- Monitor resource usage during builds"
        echo ""
        
        echo "## Log Files"
        echo ""
        echo "- **Security Log:** $SECURITY_LOG_FILE"
        echo "- **Resource Log:** $RESOURCE_LOG_FILE"
        echo ""
    } > "$report_file"
    
    log_security "INFO" "Security audit report generated: $report_file"
    echo -e "${CYAN}Security audit report: $report_file${NC}"
}

# Main security hardening function
run_security_hardening() {
    local mode="${1:-standard}"
    
    init_security_system
    log_security "INFO" "Starting security hardening (mode: $mode)"
    
    local total_issues=0
    
    # File permission hardening
    harden_file_permissions
    total_issues=$((total_issues + $?))
    
    # SSH configuration hardening
    harden_ssh_configuration
    total_issues=$((total_issues + $?))
    
    # 1Password security validation
    validate_1password_security
    total_issues=$((total_issues + $?))
    
    # Secret scanning
    scan_for_secrets
    total_issues=$((total_issues + $?))
    
    if [ "$mode" = "comprehensive" ]; then
        # Network security validation
        validate_network_security
        total_issues=$((total_issues + $?))
        
        # System integrity validation
        validate_system_integrity
        total_issues=$((total_issues + $?))
    fi
    
    # Resource optimization
    optimize_system_resources
    
    # Generate report
    generate_security_report
    
    # Summary
    if [ $total_issues -eq 0 ]; then
        log_security "SUCCESS" "Security hardening completed successfully with no issues found"
        return 0
    else
        log_security "WARN" "Security hardening completed with $total_issues issues that need attention"
        return 1
    fi
}

# Main function
main() {
    local action="${1:-harden}"
    
    case "$action" in
        "harden")
            local mode="${2:-standard}"
            run_security_hardening "$mode"
            ;;
        "permissions")
            init_security_system
            harden_file_permissions
            ;;
        "ssh")
            init_security_system
            harden_ssh_configuration
            ;;
        "1password")
            init_security_system
            validate_1password_security
            ;;
        "secrets")
            init_security_system
            scan_for_secrets
            ;;
        "network")
            init_security_system
            validate_network_security
            ;;
        "integrity")
            init_security_system
            validate_system_integrity
            ;;
        "optimize")
            init_security_system
            optimize_system_resources
            ;;
        "report")
            init_security_system
            generate_security_report
            ;;
        *)
            echo "Usage: $0 {harden|permissions|ssh|1password|secrets|network|integrity|optimize|report} [mode]"
            echo ""
            echo "Actions:"
            echo "  harden [MODE]   - Run full security hardening (MODE: standard, comprehensive)"
            echo "  permissions     - Harden file permissions only"
            echo "  ssh             - Validate SSH configuration"
            echo "  1password       - Validate 1Password security"
            echo "  secrets         - Scan for hardcoded secrets"
            echo "  network         - Validate network security"
            echo "  integrity       - Validate system integrity"
            echo "  optimize        - Optimize system resources"
            echo "  report          - Generate security report"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi