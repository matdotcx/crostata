#!/bin/bash
set -eo pipefail

# Enhanced VM Builder Environment Validator - Phase 3
# Advanced reliability improvements with comprehensive validation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Global state tracking
VALIDATION_START_TIME=$(date +%s)
VALIDATION_LOG_FILE="/tmp/vm-builder-validation-$(date +%Y%m%d-%H%M%S).log"
PERFORMANCE_DATA=()
WARNINGS=()
CRITICAL_ISSUES=()

# Parse arguments
SILENT=false
VERBOSE=false
FULL_CHECK=false
PERFORMANCE_PROFILE=false
LOG_TO_FILE=true
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--silent) SILENT=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --full) FULL_CHECK=true; shift ;;
        --performance) PERFORMANCE_PROFILE=true; shift ;;
        --no-log) LOG_TO_FILE=false; shift ;;
        -h|--help) 
            echo "VM Builder Environment Validator - Phase 3"
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -s, --silent      Silent mode (errors only)"
            echo "  -v, --verbose     Verbose output"
            echo "  --full            Comprehensive validation (slower)"
            echo "  --performance     Include performance profiling"
            echo "  --no-log          Skip logging to file"
            echo "  -h, --help        Show this help"
            exit 0 ;;
        *) break ;;
    esac
done

# Logging and monitoring functions
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$LOG_TO_FILE" = true ]; then
        echo "[$timestamp] [$level] $message" >> "$VALIDATION_LOG_FILE"
    fi
    
    case "$level" in
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        INFO) 
            if [ "$VERBOSE" = true ] || [ "$level" = "ERROR" ]; then
                echo -e "${BLUE}[INFO]${NC} $message"
            fi ;;
        DEBUG)
            if [ "$VERBOSE" = true ]; then
                echo -e "${CYAN}[DEBUG]${NC} $message"
            fi ;;
        PERF)
            if [ "$PERFORMANCE_PROFILE" = true ]; then
                echo -e "${MAGENTA}[PERF]${NC} $message"
            fi ;;
    esac
}

# Performance tracking
start_timer() {
    echo $(date +%s%3N)
}

end_timer() {
    local start_time="$1"
    local operation="$2"
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    
    PERFORMANCE_DATA+=("$operation: ${duration}ms")
    log_message "PERF" "$operation completed in ${duration}ms"
}

# Enhanced version checking
check_version_compatibility() {
    local tool="$1"
    local current_version="$2"
    local min_version="$3"
    local recommended_version="$4"
    
    log_message "DEBUG" "Checking $tool version: $current_version (min: $min_version, recommended: $recommended_version)"
    
    if command -v python3 >/dev/null 2>&1; then
        local version_check=$(python3 -c "
import sys
from packaging import version
current = version.parse('$current_version')
minimum = version.parse('$min_version')
recommended = version.parse('$recommended_version')

if current < minimum:
    print('INSUFFICIENT')
elif current < recommended:
    print('ADEQUATE')
else:
    print('OPTIMAL')
" 2>/dev/null || echo "UNKNOWN")
        
        case "$version_check" in
            INSUFFICIENT)
                CRITICAL_ISSUES+=("$tool version $current_version is below minimum required $min_version")
                return 2 ;;
            ADEQUATE)
                WARNINGS+=("$tool version $current_version is adequate but $recommended_version+ recommended")
                return 1 ;;
            OPTIMAL)
                return 0 ;;
            *)
                WARNINGS+=("Could not verify $tool version compatibility")
                return 1 ;;
        esac
    else
        # Fallback basic version comparison
        if [[ "$current_version" < "$min_version" ]]; then
            CRITICAL_ISSUES+=("$tool version $current_version appears to be below minimum $min_version")
            return 2
        fi
        return 0
    fi
}

# System resource monitoring
check_system_resources() {
    local timer=$(start_timer)
    
    log_message "INFO" "Performing comprehensive system resource check"
    
    # CPU information
    local cpu_cores=$(sysctl -n hw.ncpu)
    local cpu_brand=$(sysctl -n machdep.cpu.brand_string)
    log_message "DEBUG" "CPU: $cpu_brand ($cpu_cores cores)"
    
    if [ "$cpu_cores" -lt 4 ]; then
        WARNINGS+=("Only $cpu_cores CPU cores available, 4+ recommended for VM building")
    fi
    
    # Memory analysis
    local memory_bytes=$(sysctl -n hw.memsize)
    local memory_gb=$((memory_bytes / 1024 / 1024 / 1024))
    local memory_pressure=$(vm_stat | grep "Pages purgeable" | awk '{print $3}' | sed 's/\.//' || echo "0")
    
    log_message "DEBUG" "Memory: ${memory_gb}GB total, pressure: $memory_pressure"
    
    if [ "$memory_gb" -lt 16 ]; then
        WARNINGS+=("Only ${memory_gb}GB RAM available, 16GB+ recommended for reliable VM builds")
    fi
    
    # Disk space detailed analysis
    local disk_info=$(df -h . | tail -1)
    local available_space=$(echo "$disk_info" | awk '{print $4}')
    local used_percent=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
    
    log_message "DEBUG" "Disk: $available_space available, ${used_percent}% used"
    
    if [ "$used_percent" -gt 85 ]; then
        CRITICAL_ISSUES+=("Disk usage at ${used_percent}%, may cause build failures")
    elif [ "$used_percent" -gt 70 ]; then
        WARNINGS+=("Disk usage at ${used_percent}%, monitor space during builds")
    fi
    
    # Network latency test
    if [ "$FULL_CHECK" = true ]; then
        local ping_time=$(ping -c 1 8.8.8.8 2>/dev/null | grep time= | sed 's/.*time=//' | sed 's/ ms//' || echo "999")
        log_message "DEBUG" "Network latency: ${ping_time}ms"
        
        if (( $(echo "$ping_time > 100" | bc -l 2>/dev/null || echo "0") )); then
            WARNINGS+=("High network latency (${ping_time}ms) may affect download speeds")
        fi
    fi
    
    end_timer "$timer" "System resource check"
}

# Enhanced security validation
check_security_configuration() {
    local timer=$(start_timer)
    
    log_message "INFO" "Performing security configuration validation"
    
    # Check SIP status
    local sip_status=$(csrutil status 2>/dev/null | grep -o "enabled\|disabled" || echo "unknown")
    log_message "DEBUG" "System Integrity Protection: $sip_status"
    
    # Check Gatekeeper
    local gatekeeper_status=$(spctl --status 2>/dev/null | grep -o "enabled\|disabled" || echo "unknown")
    log_message "DEBUG" "Gatekeeper: $gatekeeper_status"
    
    # Check for suspicious processes
    if [ "$FULL_CHECK" = true ]; then
        local suspicious_procs=$(ps aux | grep -E "(mining|crypto|torrent)" | grep -v grep | wc -l)
        if [ "$suspicious_procs" -gt 0 ]; then
            WARNINGS+=("Detected $suspicious_procs potentially resource-intensive processes")
        fi
    fi
    
    # File permissions check
    local script_perms=$(stat -f "%A" "$0")
    if [ "$script_perms" -ne 755 ] && [ "$script_perms" -ne 644 ]; then
        WARNINGS+=("Script permissions ($script_perms) may be overly permissive")
    fi
    
    end_timer "$timer" "Security validation"
}

# Dependency version matrix
MIN_VERSION_PACKER="1.9.0"
MIN_VERSION_TART="2.6.0"
MIN_VERSION_OP="2.20.0"
MIN_VERSION_JQ="1.6"

RECOMMENDED_VERSION_PACKER="1.10.0"
RECOMMENDED_VERSION_TART="2.7.0"
RECOMMENDED_VERSION_OP="2.22.0"
RECOMMENDED_VERSION_JQ="1.7"

# Output header
if [ "$VERBOSE" = true ]; then
    echo -e "${BLUE}🔍 VM Builder Environment Validator - Phase 3${NC}"
    echo "=================================================="
    echo -e "${CYAN}Validation started at $(date)${NC}"
    if [ "$LOG_TO_FILE" = true ]; then
        echo -e "${CYAN}Logging to: $VALIDATION_LOG_FILE${NC}"
    fi
    echo ""
fi

log_message "INFO" "Starting enhanced validation with $([ "$FULL_CHECK" = true ] && echo "full" || echo "standard") checks"

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

section "Checking Dependencies with Version Validation"

# Enhanced dependency checking with version validation
check_dependency_versions() {
    local timer=$(start_timer)
    
    for tool in op packer tart ssh-keygen jq; do
        if command -v "$tool" &> /dev/null; then
            log_message "DEBUG" "Found $tool, checking version compatibility"
            
            # Get version information
            local version=""
            case "$tool" in
                op) version=$(op --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown") ;;
                packer) version=$(packer version 2>/dev/null | head -1 | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | sed 's/v//' || echo "unknown") ;;
                tart) version=$(tart --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown") ;;
                ssh-keygen) 
                    # ssh-keygen doesn't have a standard version flag, check if it works
                    if ssh-keygen -t rsa -N "" -f /tmp/test_key_$$ &>/dev/null; then
                        rm -f /tmp/test_key_$$ /tmp/test_key_$$.pub
                        version="available"
                    else
                        version="unknown"
                    fi ;;
                jq) version=$(jq --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' || echo "unknown") ;;
            esac
            
            if [ "$version" = "unknown" ] || [ "$version" = "" ]; then
                WARNINGS+=("Could not determine $tool version")
                report_test "Found $tool" true "version unknown"
            elif [ "$tool" = "ssh-keygen" ]; then
                report_test "Found $tool" true "functional"
            else
                # Check version compatibility for tools with version requirements
                local min_ver=""
                local rec_ver=""
                case "$tool" in
                    "packer") min_ver="$MIN_VERSION_PACKER"; rec_ver="$RECOMMENDED_VERSION_PACKER" ;;
                    "tart") min_ver="$MIN_VERSION_TART"; rec_ver="$RECOMMENDED_VERSION_TART" ;;
                    "op") min_ver="$MIN_VERSION_OP"; rec_ver="$RECOMMENDED_VERSION_OP" ;;
                    "jq") min_ver="$MIN_VERSION_JQ"; rec_ver="$RECOMMENDED_VERSION_JQ" ;;
                esac
                
                if [ -n "$min_ver" ] && [ -n "$rec_ver" ]; then
                    check_version_compatibility "$tool" "$version" "$min_ver" "$rec_ver"
                    local compat_result=$?
                    
                    case $compat_result in
                        0) report_test "Found $tool v$version" true "optimal version" ;;
                        1) report_test "Found $tool v$version" true "adequate (update recommended)" ;;
                        2) 
                            report_test "Found $tool v$version" false "version too old (minimum: $min_ver)"
                            VALIDATION_PASSED=false ;;
                    esac
                else
                    report_test "Found $tool v$version" true ""
                fi
            fi
        else
            case "$tool" in
                op) suggest="brew install 1password-cli" ;;
                packer) suggest="brew install hashicorp/tap/packer" ;;
                tart) suggest="brew install cirruslabs/cli/tart" ;;
                ssh-keygen) suggest="Should be pre-installed on macOS" ;;
                jq) suggest="brew install jq" ;;
            esac
            FAILURES+=("$tool: $suggest")
            VALIDATION_PASSED=false
            report_test "Found $tool" false "Install with: $suggest"
        fi
    done
    
    end_timer "$timer" "Dependency version check"
}

check_dependency_versions

# Additional runtime dependency checks
if [ "$FULL_CHECK" = true ]; then
    section "Checking Runtime Dependencies"
    
    # Check Python for packaging module
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import packaging.version" 2>/dev/null; then
            report_test "Python packaging module" true ""
        else
            WARNINGS+=("Python packaging module not available, install with: pip3 install packaging")
            report_test "Python packaging module" false "Enhanced version checking disabled"
        fi
    fi
    
    # Check bc for numeric comparisons
    if ! command -v bc >/dev/null 2>&1; then
        WARNINGS+=("bc calculator not found, some calculations may be limited")
        report_test "bc calculator" false "install with: brew install bc"
    else
        report_test "bc calculator" true ""
    fi
    
    # Check system python versus homebrew python
    if command -v python3 >/dev/null 2>&1; then
        local python_path=$(which python3)
        if [[ "$python_path" == *"/usr/bin/python3" ]]; then
            log_message "DEBUG" "Using system Python: $python_path"
        else
            log_message "DEBUG" "Using custom Python: $python_path"
        fi
    fi
fi

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

section "System Requirements and Performance Analysis"

# Perform comprehensive system resource check
check_system_resources

# Legacy compatibility checks
AVAILABLE_SPACE_KB=$(df . | tail -1 | awk '{print $4}')
AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE_KB / 1024 / 1024))

if [ "$AVAILABLE_SPACE_GB" -ge 50 ]; then
    report_test "Disk space (50GB+ recommended)" true "Available: ${AVAILABLE_SPACE_GB}GB"
else
    report_test "Disk space (50GB+ recommended)" false "Available: ${AVAILABLE_SPACE_GB}GB (may be insufficient for IPSW builds)"
fi

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
    VALIDATION_PASSED=false
    FAILURES+=("Apple Silicon CPU: Tart requires Apple Silicon (M1/M2/M3/M4)")
fi

# Enhanced macOS version checking
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
MACOS_MINOR=$(echo "$MACOS_VERSION" | cut -d. -f2)

log_message "DEBUG" "macOS version: $MACOS_VERSION (major: $MACOS_MAJOR, minor: $MACOS_MINOR)"

if [ "$MACOS_MAJOR" -ge 13 ]; then
    if [ "$MACOS_MAJOR" -ge 14 ]; then
        report_test "macOS version (13.0+ required)" true "Running: $MACOS_VERSION (excellent)"
    else
        report_test "macOS version (13.0+ required)" true "Running: $MACOS_VERSION (good)"
    fi
else
    report_test "macOS version (13.0+ required)" false "Running: $MACOS_VERSION (too old)"
    VALIDATION_PASSED=false
    FAILURES+=("macOS version: Requires 13.0+, found $MACOS_VERSION")
fi

# Run security configuration check
if [ "$FULL_CHECK" = true ]; then
    section "Security Configuration"
    check_security_configuration
fi

# Generate comprehensive validation report
generate_validation_report() {
    local total_time=$(($(date +%s) - VALIDATION_START_TIME))
    
    log_message "INFO" "Validation completed in ${total_time}s"
    
    if [ "$LOG_TO_FILE" = true ]; then
        {
            echo ""
            echo "=== VALIDATION SUMMARY ==="
            echo "Total validation time: ${total_time}s"
            echo "Critical issues: ${#CRITICAL_ISSUES[@]}"
            echo "Warnings: ${#WARNINGS[@]}"
            echo "Failures: ${#FAILURES[@]}"
            echo ""
            
            if [ ${#PERFORMANCE_DATA[@]} -gt 0 ]; then
                echo "=== PERFORMANCE DATA ==="
                for perf in "${PERFORMANCE_DATA[@]}"; do
                    echo "$perf"
                done
                echo ""
            fi
            
            if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
                echo "=== CRITICAL ISSUES ==="
                for issue in "${CRITICAL_ISSUES[@]}"; do
                    echo "• $issue"
                done
                echo ""
            fi
            
            if [ ${#WARNINGS[@]} -gt 0 ]; then
                echo "=== WARNINGS ==="
                for warning in "${WARNINGS[@]}"; do
                    echo "• $warning"
                done
                echo ""
            fi
            
            if [ ${#FAILURES[@]} -gt 0 ]; then
                echo "=== FAILURES ==="
                for failure in "${FAILURES[@]}"; do
                    echo "• $failure"
                done
                echo ""
            fi
        } >> "$VALIDATION_LOG_FILE"
    fi
}

# Results handling with enhanced reporting
generate_validation_report

if [ "$VALIDATION_PASSED" = true ] && [ ${#CRITICAL_ISSUES[@]} -eq 0 ]; then
    if [ "$SILENT" = false ]; then
        echo -e "${GREEN}✅ Environment validation passed${NC} - Ready to build VMs"
        
        if [ ${#WARNINGS[@]} -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}⚠️  ${#WARNINGS[@]} warning(s) detected:${NC}"
            for warning in "${WARNINGS[@]}"; do
                echo -e "  ${YELLOW}•${NC} $warning"
            done
            echo ""
            echo -e "${BLUE}These warnings won't prevent building but may affect performance.${NC}"
        fi
        
        if [ "$PERFORMANCE_PROFILE" = true ] && [ ${#PERFORMANCE_DATA[@]} -gt 0 ]; then
            echo ""
            echo -e "${MAGENTA}📊 Performance Profile:${NC}"
            for perf in "${PERFORMANCE_DATA[@]}"; do
                echo -e "  ${MAGENTA}•${NC} $perf"
            done
        fi
        
        if [ "$LOG_TO_FILE" = true ]; then
            echo ""
            echo -e "${CYAN}📝 Detailed log saved to: $VALIDATION_LOG_FILE${NC}"
        fi
    fi
    exit 0
else
    echo -e "${RED}❌ Environment validation failed${NC}"
    echo ""
    
    if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
        echo -e "${RED}🚨 Critical issues found (${#CRITICAL_ISSUES[@]}):${NC}"
        for issue in "${CRITICAL_ISSUES[@]}"; do
            echo -e "  ${RED}•${NC} $issue"
        done
        echo ""
    fi
    
    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo -e "${RED}❌ Validation failures (${#FAILURES[@]}):${NC}"
        for failure in "${FAILURES[@]}"; do
            echo -e "  ${RED}•${NC} $failure"
        done
        echo ""
    fi
    
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Additional warnings (${#WARNINGS[@]}):${NC}"
        for warning in "${WARNINGS[@]}"; do
            echo -e "  ${YELLOW}•${NC} $warning"
        done
        echo ""
    fi
    
    echo -e "${BLUE}💡 Troubleshooting tips:${NC}"
    echo "  • Run with --verbose for detailed output"
    echo "  • Run with --full for comprehensive checks"
    echo "  • Check scripts/error-recovery.sh for automated fixes"
    if [ "$LOG_TO_FILE" = true ]; then
        echo "  • Review detailed log: $VALIDATION_LOG_FILE"
    fi
    echo "  • Fix issues above, then run ./build-with-1password.sh"
    
    exit 1
fi