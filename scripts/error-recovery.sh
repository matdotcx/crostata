#!/bin/bash
# Advanced Error Recovery System for Packer VM Builds - Phase 3
# This script provides comprehensive error detection, recovery mechanisms, and state management

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Global configuration
RECOVERY_LOG_DIR="/tmp/vm-builder-recovery"
STATE_FILE="$RECOVERY_LOG_DIR/recovery-state.json"
DIAGNOSTIC_LOG="$RECOVERY_LOG_DIR/diagnostic-$(date +%Y%m%d-%H%M%S).log"
RECOVERY_SESSION_ID=$(date +%s%N | cut -c1-13)
MONITORING_ENABLED=true
MAX_RECOVERY_ATTEMPTS=3

# Initialize recovery system
init_recovery_system() {
    mkdir -p "$RECOVERY_LOG_DIR"
    
    # Initialize state file if it doesn't exist
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" << EOF
{
  "recovery_sessions": {},
  "system_state": {
    "last_validation": null,
    "last_build_attempt": null,
    "last_recovery_attempt": null,
    "failure_patterns": {}
  },
  "metrics": {
    "total_recoveries": 0,
    "successful_recoveries": 0,
    "failed_recoveries": 0
  }
}
EOF
    fi
}

# Enhanced logging with state tracking
log() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $message"
    echo "[$timestamp] [INFO] $message" >> "$DIAGNOSTIC_LOG"
}

warn() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[WARNING]${NC} $message"
    echo "[$timestamp] [WARN] $message" >> "$DIAGNOSTIC_LOG"
}

error() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR]${NC} $message"
    echo "[$timestamp] [ERROR] $message" >> "$DIAGNOSTIC_LOG"
}

success() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    echo "[$timestamp] [SUCCESS] $message" >> "$DIAGNOSTIC_LOG"
}

debug() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}[DEBUG]${NC} $message"
    echo "[$timestamp] [DEBUG] $message" >> "$DIAGNOSTIC_LOG"
}

# State management functions
save_recovery_state() {
    local session_id="$1"
    local operation="$2"
    local status="$3"
    local details="$4"
    
    if command -v jq >/dev/null 2>&1; then
        jq --arg sid "$session_id" \
           --arg op "$operation" \
           --arg st "$status" \
           --arg det "$details" \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.recovery_sessions[$sid] = {
             "operation": $op,
             "status": $st,
             "details": $det,
             "timestamp": $ts
           }' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    
    debug "Saved recovery state for session $session_id: $operation -> $status"
}

load_recovery_state() {
    local session_id="$1"
    
    if command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
        jq -r --arg sid "$session_id" '.recovery_sessions[$sid] // empty' "$STATE_FILE"
    fi
}

update_metrics() {
    local metric="$1"
    
    if command -v jq >/dev/null 2>&1; then
        jq --arg metric "$metric" \
           '.metrics[$metric] = (.metrics[$metric] // 0) + 1' \
           "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
}

# System diagnostics collection
collect_system_diagnostics() {
    log "Collecting comprehensive system diagnostics..."
    
    local diag_file="$RECOVERY_LOG_DIR/system-diagnostics-$(date +%Y%m%d-%H%M%S).json"
    
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"session_id\": \"$RECOVERY_SESSION_ID\","
        echo "  \"system_info\": {"
        echo "    \"os_version\": \"$(sw_vers -productVersion)\","
        echo "    \"build_version\": \"$(sw_vers -buildVersion)\","
        echo "    \"hardware\": \"$(system_profiler SPHardwareDataType | grep 'Model Identifier' | awk '{print $3}')\","
        echo "    \"cpu\": \"$(sysctl -n machdep.cpu.brand_string)\","
        echo "    \"memory_gb\": $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )),"
        echo "    \"uptime_seconds\": $(sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//' | xargs -I {} bash -c 'echo $(($(date +%s) - {}))')"
        echo "  },"
        echo "  \"network_status\": {"
        echo "    \"interfaces\": ["
        # Use networksetup (macOS native) with fallback
        if command -v networksetup >/dev/null 2>&1; then
            networksetup -listallhardwareports 2>/dev/null | grep "Hardware Port" | while read -r line; do
                port=$(echo "$line" | sed 's/Hardware Port: //')
                echo "      \"$port\""
            done | head -3
        else
            # Fallback to interface listing if networksetup fails
            ifconfig -l 2>/dev/null | tr ' ' '\n' | head -3 | sed 's/^/      "/' | sed 's/$/"/'
        fi
        echo "    ],"
        echo "    \"dns_servers\": ["
        # Use scutil (macOS native) with fallback
        if command -v scutil >/dev/null 2>&1; then
            scutil --dns 2>/dev/null | grep nameserver | head -3 | awk '{print "      \"" $3 "\""}' || echo "      \"8.8.8.8\""
        else
            # Fallback to common DNS servers
            echo "      \"8.8.8.8\""
            echo "      \"1.1.1.1\""
        fi
        echo "    ]"
        echo "  },"
        echo "  \"disk_usage\": {"
        df -h / | tail -1 | awk '{
            print "    \"total\": \"" $2 "\","
            print "    \"used\": \"" $3 "\","
            print "    \"available\": \"" $4 "\","
            print "    \"usage_percent\": \"" $5 "\""
        }'
        echo "  },"
        echo "  \"processes\": {"
        echo "    \"total_count\": $(ps aux | wc -l),"
        echo "    \"high_cpu\": ["
        ps aux | sort -rn -k 3 | head -5 | tail -4 | awk '{print "      {\"pid\": " $2 ", \"cpu\": " $3 ", \"command\": \"" $11 "\"}"}'
        echo "    ],"
        echo "    \"high_memory\": ["
        ps aux | sort -rn -k 4 | head -5 | tail -4 | awk '{print "      {\"pid\": " $2 ", \"mem\": " $4 ", \"command\": \"" $11 "\"}"}'
        echo "    ]"
        echo "  }"
        echo "}"
    } > "$diag_file" 2>/dev/null || {
        warn "Failed to generate complete diagnostics, creating basic version"
        echo "{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"error\": \"Partial diagnostics collection\"}" > "$diag_file"
    }
    
    debug "System diagnostics saved to: $diag_file"
    return 0
}

# Enhanced retry function with state tracking
retry_with_backoff() {
    local max_attempts=$1
    local delay=$2
    local command="${@:3}"
    local attempt=1
    local operation_id="retry_$(echo "$command" | tr ' ' '_' | cut -c1-20)"
    
    save_recovery_state "$RECOVERY_SESSION_ID" "$operation_id" "started" "Retrying command: $command"
    
    while [ $attempt -le $max_attempts ]; do
        log "Attempt $attempt/$max_attempts: $command"
        
        if eval "$command"; then
            success "Command succeeded on attempt $attempt"
            save_recovery_state "$RECOVERY_SESSION_ID" "$operation_id" "success" "Succeeded on attempt $attempt"
            update_metrics "successful_recoveries"
            return 0
        else
            if [ $attempt -eq $max_attempts ]; then
                error "Command failed after $max_attempts attempts"
                save_recovery_state "$RECOVERY_SESSION_ID" "$operation_id" "failed" "Failed after $max_attempts attempts"
                update_metrics "failed_recoveries"
                return 1
            fi
            
            warn "Command failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
            attempt=$((attempt + 1))
        fi
    done
}

# Advanced error pattern detection
detect_error_patterns() {
    local error_log="$1"
    local patterns=()
    
    if [ ! -f "$error_log" ]; then
        warn "Error log file not found: $error_log"
        return 1
    fi
    
    # Common Packer error patterns
    if grep -q "connection timeout" "$error_log"; then
        patterns+=("network_timeout")
    fi
    
    if grep -q "SSH handshake error" "$error_log"; then
        patterns+=("ssh_handshake")
    fi
    
    if grep -q "No space left on device" "$error_log"; then
        patterns+=("disk_full")
    fi
    
    if grep -q "VNC connection failed" "$error_log"; then
        patterns+=("vnc_connection")
    fi
    
    if grep -q "1Password CLI" "$error_log"; then
        patterns+=("onepassword_auth")
    fi
    
    if grep -q "tart" "$error_log" && grep -q "command not found\|permission denied" "$error_log"; then
        patterns+=("tart_permission")
    fi
    
    if [ ${#patterns[@]} -gt 0 ]; then
        log "Detected error patterns: ${patterns[*]}"
        for pattern in "${patterns[@]}"; do
            save_recovery_state "$RECOVERY_SESSION_ID" "error_pattern_$pattern" "detected" "Pattern found in $error_log"
        done
    fi
    
    echo "${patterns[@]}"
}

# Intelligent recovery strategies based on error patterns
apply_recovery_strategy() {
    local error_patterns=("$@")
    local recovery_success=true
    
    for pattern in "${error_patterns[@]}"; do
        log "Applying recovery strategy for pattern: $pattern"
        
        case "$pattern" in
            "network_timeout")
                log "Applying network timeout recovery..."
                if ! validate_network_recovery; then
                    recovery_success=false
                fi ;;
            "ssh_handshake")
                log "Applying SSH handshake recovery..."
                if ! validate_ssh_advanced; then
                    recovery_success=false
                fi ;;
            "disk_full")
                log "Applying disk space recovery..."
                if ! cleanup_disk_space; then
                    recovery_success=false
                fi ;;
            "vnc_connection")
                log "Applying VNC connection recovery..."
                if ! validate_vnc_advanced; then
                    recovery_success=false
                fi ;;
            "onepassword_auth")
                log "Applying 1Password authentication recovery..."
                if ! recover_onepassword_auth; then
                    recovery_success=false
                fi ;;
            "tart_permission")
                log "Applying Tart permission recovery..."
                if ! recover_tart_permissions; then
                    recovery_success=false
                fi ;;
            *)
                warn "Unknown error pattern: $pattern" ;;
        esac
    done
    
    if [ "$recovery_success" = true ]; then
        success "All recovery strategies applied successfully"
        return 0
    else
        error "Some recovery strategies failed"
        return 1
    fi
}

# Advanced network recovery
validate_network_recovery() {
    log "Performing advanced network validation and recovery..."
    
    # Check DNS resolution with multiple servers
    local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    local dns_success=false
    
    for dns in "${dns_servers[@]}"; do
        if nslookup google.com "$dns" >/dev/null 2>&1; then
            debug "DNS resolution successful via $dns"
            dns_success=true
            break
        fi
    done
    
    if [ "$dns_success" = false ]; then
        warn "DNS resolution failed, attempting to flush DNS cache"
        sudo dscacheutil -flushcache
        sudo killall -HUP mDNSResponder
        sleep 2
        
        # Retry DNS test
        if nslookup google.com >/dev/null 2>&1; then
            success "DNS resolution recovered after cache flush"
        else
            error "DNS resolution still failing after recovery attempt"
            return 1
        fi
    fi
    
    # Test network latency and bandwidth
    local ping_test=$(ping -c 3 google.com 2>/dev/null | grep avg | awk '{print $4}' | cut -d'/' -f2 || echo "999")
    if (( $(echo "$ping_test > 500" | bc -l 2>/dev/null || echo "0") )); then
        warn "High network latency detected: ${ping_test}ms"
    fi
    
    success "Network validation and recovery completed"
    return 0
}

# Advanced disk space cleanup
cleanup_disk_space() {
    log "Performing intelligent disk space cleanup..."
    
    local initial_space=$(df / | tail -1 | awk '{print $4}')
    
    # Clean Packer temporary files
    find /tmp -name "packer-*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    find /var/tmp -name "packer-*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    
    # Clean VM builder specific temporary files
    rm -rf /tmp/vm-builder-temp-* 2>/dev/null || true
    
    # Clean old log files
    find "$RECOVERY_LOG_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    # Clear system caches (if safe to do so)
    if command -v purge >/dev/null 2>&1; then
        debug "Purging system memory caches"
        sudo purge 2>/dev/null || true
    fi
    
    local final_space=$(df / | tail -1 | awk '{print $4}')
    local freed_space=$((final_space - initial_space))
    
    if [ "$freed_space" -gt 0 ]; then
        success "Freed up ${freed_space}KB of disk space"
    else
        warn "No significant disk space was freed"
    fi
    
    return 0
}

# 1Password authentication recovery
recover_onepassword_auth() {
    log "Attempting 1Password authentication recovery..."
    
    # Check if already authenticated
    if op account list >/dev/null 2>&1; then
        success "1Password already authenticated"
        return 0
    fi
    
    # Try to sign in interactively if possible
    warn "1Password authentication required"
    echo "Please run 'op signin' manually to authenticate with 1Password"
    echo "After authentication, you can continue with the build process"
    
    return 1
}

# Tart permissions recovery
recover_tart_permissions() {
    log "Attempting Tart permissions recovery..."
    
    # Check if Tart is installed and accessible
    if ! command -v tart >/dev/null 2>&1; then
        error "Tart is not installed or not in PATH"
        return 1
    fi
    
    # Check if we can run basic Tart commands
    if ! tart list >/dev/null 2>&1; then
        warn "Tart permissions may be insufficient"
        echo "You may need to grant necessary permissions to Tart in System Preferences"
        echo "Check Privacy & Security > Full Disk Access and Virtualization settings"
        return 1
    fi
    
    success "Tart permissions appear to be correct"
    return 0
}

# SSH service validation and recovery
validate_ssh() {
    log "Validating SSH service..."
    
    # Check if SSH is enabled
    if ! sudo systemsetup -getremotelogin | grep -q "Remote Login: On"; then
        warn "SSH is not enabled, attempting to enable..."
        retry_with_backoff 3 2 "sudo systemsetup -setremotelogin on"
    fi
    
    # Check if SSH daemon is running
    if ! sudo launchctl list | grep -q ssh; then
        warn "SSH daemon not running, attempting to start..."
        retry_with_backoff 3 2 "sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist"
    fi
    
    # Check if SSH port is listening (macOS-compatible)
    if ! netstat -an | grep -E '(tcp|tcp4|tcp6).*\.22[[:space:]].*LISTEN' >/dev/null 2>&1; then
        error "SSH port 22 is not listening"
        return 1
    fi
    
    success "SSH service is running and accessible"
    return 0
}

# VNC service validation and recovery  
validate_vnc() {
    log "Validating VNC/Screen Sharing service..."
    
    # Check if screen sharing is enabled (macOS-compatible)
    if ! netstat -an | grep -E '(tcp|tcp4|tcp6).*\.5900[[:space:]].*LISTEN' >/dev/null 2>&1; then
        warn "VNC port not listening, attempting to enable screen sharing..."
        
        # Enable screen sharing with retry
        retry_with_backoff 3 3 "sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -restart -agent -menu"
        
        # Configure screen sharing daemon
        sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false
        sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist || true
        
        sleep 5  # Give service time to start
    fi
    
    if netstat -an | grep -E '(tcp|tcp4|tcp6).*\.5900[[:space:]].*LISTEN' >/dev/null 2>&1; then
        success "VNC service is running and accessible"
        return 0
    else
        warn "VNC service may not be fully accessible"
        return 1
    fi
}

# System health validation
validate_system_health() {
    log "Performing system health validation..."
    
    # Check disk space
    local disk_usage
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        error "Disk usage is ${disk_usage}%, which is critically high"
        return 1
    fi
    
    # Check memory
    local memory_pressure
    if command -v vm_stat >/dev/null; then
        memory_pressure=$(vm_stat | grep "Pages purgeable" | awk '{print $3}' | sed 's/\.//')
        if [ "${memory_pressure:-0}" -gt 1000000 ]; then
            warn "High memory pressure detected"
        fi
    fi
    
    # Check load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_avg > 10" | bc -l 2>/dev/null || echo "0") )); then
        warn "High system load detected: $load_avg"
    fi
    
    success "System health validation passed"
    return 0
}

# Network connectivity validation
validate_network() {
    log "Validating network connectivity..."
    
    # Check if we can resolve DNS
    if ! nslookup google.com >/dev/null 2>&1; then
        error "DNS resolution failed"
        return 1
    fi
    
    # Check if we can reach external hosts
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error "External network connectivity failed"
        return 1
    fi
    
    success "Network connectivity validated"
    return 0
}

# User and permissions validation
validate_user_setup() {
    local username=$1
    log "Validating user setup for: $username"
    
    # Check if user exists
    if ! dscl . -read "/Users/$username" >/dev/null 2>&1; then
        error "User $username does not exist"
        return 1
    fi
    
    # Check if user is in admin group
    if ! dscl . -read /Groups/admin GroupMembership | grep -q "$username"; then
        warn "User $username is not in admin group"
    fi
    
    # Check passwordless sudo
    if ! sudo -u "$username" sudo -n true 2>/dev/null; then
        warn "Passwordless sudo not configured for $username"
    fi
    
    # Check SSH key setup
    if [ -f "/Users/$username/.ssh/authorized_keys" ]; then
        if ssh-keygen -l -f "/Users/$username/.ssh/authorized_keys" >/dev/null 2>&1; then
            success "SSH keys are properly configured for $username"
        else
            error "SSH keys are invalid for $username"
            return 1
        fi
    else
        warn "No SSH keys found for $username"
    fi
    
    success "User setup validation completed for $username"
    return 0
}

# Cleanup function for failed builds
cleanup_failed_build() {
    log "Performing cleanup for failed build..."
    
    # Clean up temporary files
    sudo rm -rf /tmp/packer-* || true
    sudo rm -rf /var/tmp/packer-* || true
    
    # Reset SSH configuration if corrupted
    if [ -f /etc/ssh/sshd_config.backup ]; then
        sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
        sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
        sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
    fi
    
    log "Cleanup completed"
}

# Enhanced validation functions with advanced recovery
validate_ssh_advanced() {
    log "Performing advanced SSH validation and recovery..."
    
    # Enhanced SSH validation with more comprehensive checks
    if validate_ssh; then
        return 0
    fi
    
    # If basic validation failed, try advanced recovery
    warn "Basic SSH validation failed, attempting advanced recovery..."
    
    # Check for SSH configuration issues
    if [ -f /etc/ssh/sshd_config ]; then
        # Backup current config
        sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.recovery_backup
        
        # Check for common misconfigurations
        if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config; then
            warn "Root login is enabled, which may be a security concern"
        fi
        
        # Ensure SSH is properly configured for key authentication
        if ! grep -q "PubkeyAuthentication yes" /etc/ssh/sshd_config; then
            warn "PubkeyAuthentication may not be enabled"
        fi
    fi
    
    # Try to restart SSH service
    log "Attempting to restart SSH service..."
    if retry_with_backoff 3 5 "sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist && sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist"; then
        success "SSH service restarted successfully"
        return 0
    else
        error "Failed to restart SSH service"
        return 1
    fi
}

validate_vnc_advanced() {
    log "Performing advanced VNC validation and recovery..."
    
    # Enhanced VNC validation with more comprehensive checks
    if validate_vnc; then
        return 0
    fi
    
    # If basic validation failed, try advanced recovery
    warn "Basic VNC validation failed, attempting advanced recovery..."
    
    # Try alternative methods to enable screen sharing
    log "Attempting alternative screen sharing configuration..."
    
    # Use system preferences to enable screen sharing
    sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false
    
    # Enable ARD (Apple Remote Desktop) which includes VNC
    if command -v /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart >/dev/null 2>&1; then
        retry_with_backoff 3 5 "sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -restart -agent"
    fi
    
    # Wait for service to start and test again
    sleep 5
    if netstat -an | grep -E '(tcp|tcp4|tcp6).*\.5900[[:space:]].*LISTEN' >/dev/null 2>&1; then
        success "VNC service recovered successfully"
        return 0
    else
        error "Failed to recover VNC service"
        return 1
    fi
}

# Comprehensive recovery orchestrator
run_comprehensive_recovery() {
    local error_log="${1:-}"
    local recovery_mode="${2:-auto}"
    
    log "Starting comprehensive recovery process (mode: $recovery_mode)"
    init_recovery_system
    save_recovery_state "$RECOVERY_SESSION_ID" "comprehensive_recovery" "started" "Starting comprehensive recovery"
    
    # Collect system diagnostics first
    collect_system_diagnostics
    
    # Detect error patterns if log file is provided
    local detected_patterns=()
    if [ -n "$error_log" ] && [ -f "$error_log" ]; then
        log "Analyzing error patterns from: $error_log"
        mapfile -t detected_patterns < <(detect_error_patterns "$error_log")
    fi
    
    # Apply targeted recovery strategies
    if [ ${#detected_patterns[@]} -gt 0 ]; then
        log "Applying targeted recovery strategies for detected patterns"
        if apply_recovery_strategy "${detected_patterns[@]}"; then
            success "Targeted recovery strategies completed successfully"
        else
            warn "Some targeted recovery strategies failed, proceeding with general recovery"
        fi
    fi
    
    # Run general system validations and recovery
    log "Running general system validation and recovery..."
    local general_success=true
    
    if ! validate_network_recovery; then
        warn "Network recovery failed"
        general_success=false
    fi
    
    if ! validate_ssh_advanced; then
        warn "Advanced SSH recovery failed"
        general_success=false
    fi
    
    if ! validate_vnc_advanced; then
        warn "Advanced VNC recovery failed"
        general_success=false
    fi
    
    if ! validate_system_health; then
        warn "System health validation failed"
        general_success=false
    fi
    
    if ! cleanup_disk_space; then
        warn "Disk space cleanup had issues"
    fi
    
    # Generate recovery report
    local recovery_status
    if [ "$general_success" = true ]; then
        recovery_status="success"
        success "Comprehensive recovery completed successfully"
    else
        recovery_status="partial"
        warn "Comprehensive recovery completed with some issues"
    fi
    
    save_recovery_state "$RECOVERY_SESSION_ID" "comprehensive_recovery" "$recovery_status" "Recovery process completed"
    update_metrics "total_recoveries"
    
    # Print recovery summary
    print_recovery_summary
    
    return $([ "$general_success" = true ] && echo 0 || echo 1)
}

# Print comprehensive recovery summary
print_recovery_summary() {
    echo ""
    echo -e "${CYAN}=== Recovery Session Summary ===${NC}"
    echo -e "${CYAN}Session ID:${NC} $RECOVERY_SESSION_ID"
    echo -e "${CYAN}Diagnostics Log:${NC} $DIAGNOSTIC_LOG"
    echo -e "${CYAN}State File:${NC} $STATE_FILE"
    
    if command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
        local total_recoveries=$(jq -r '.metrics.total_recoveries // 0' "$STATE_FILE")
        local successful_recoveries=$(jq -r '.metrics.successful_recoveries // 0' "$STATE_FILE")
        local failed_recoveries=$(jq -r '.metrics.failed_recoveries // 0' "$STATE_FILE")
        
        echo -e "${CYAN}Total Recovery Sessions:${NC} $total_recoveries"
        echo -e "${CYAN}Successful Recoveries:${NC} $successful_recoveries"
        echo -e "${CYAN}Failed Recoveries:${NC} $failed_recoveries"
    fi
    
    echo -e "${CYAN}Recovery Logs Directory:${NC} $RECOVERY_LOG_DIR"
    echo ""
}

# Main function with enhanced capabilities
main() {
    local username=${1:-""}
    local mode=${2:-"full"}
    local error_log=${3:-""}
    
    log "Starting Advanced Error Recovery System - Phase 3"
    log "Mode: $mode, Username: ${username:-none}, Error Log: ${error_log:-none}"
    
    # Initialize recovery system
    init_recovery_system
    
    case $mode in
        "ssh")
            validate_ssh_advanced
            ;;
        "vnc")
            validate_vnc_advanced
            ;;
        "network")
            validate_network_recovery
            ;;
        "user")
            if [ -z "$username" ]; then
                error "Username required for user validation"
                exit 1
            fi
            validate_user_setup "$username"
            ;;
        "cleanup")
            cleanup_disk_space
            ;;
        "diagnostics")
            collect_system_diagnostics
            ;;
        "comprehensive")
            run_comprehensive_recovery "$error_log" "auto"
            ;;
        "patterns")
            if [ -n "$error_log" ]; then
                detect_error_patterns "$error_log"
            else
                error "Error log file required for pattern detection"
                exit 1
            fi
            ;;
        "full"|*)
            run_comprehensive_recovery "$error_log" "full"
            ;;
    esac
    
    local exit_code=$?
    success "Advanced Error Recovery System completed"
    exit $exit_code
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi