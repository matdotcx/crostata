#!/bin/bash
# VM Builder Comprehensive Testing Framework - Phase 3
# Provides automated testing, validation, and integration testing capabilities

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
TEST_LOG_DIR="/tmp/vm-builder-tests"
TEST_SESSION_ID=$(date +%s%N | cut -c1-13)
TEST_RESULTS_FILE="$TEST_LOG_DIR/test-results-$(date +%Y%m%d-%H%M%S).json"
INTEGRATION_LOG="$TEST_LOG_DIR/integration-test.log"
PERFORMANCE_TEST_LOG="$TEST_LOG_DIR/performance-test.log"

# Cross-platform timeout function
# On macOS, GNU coreutils timeout is 'gtimeout'
# On Linux, it's usually just 'timeout'
get_timeout_command() {
    if command -v gtimeout >/dev/null 2>&1; then
        echo "gtimeout"
    elif command -v timeout >/dev/null 2>&1; then
        echo "timeout"
    else
        echo ""
    fi
}

# Get the appropriate timeout command for this system
TIMEOUT_CMD=$(get_timeout_command)

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test configuration
TIMEOUT_SECONDS="300"
RETRY_ATTEMPTS="3"
PERFORMANCE_BASELINE_FACTOR="1.5"
INTEGRATION_TEST_VM_NAME="test-vm-integration"

# Test categories and their descriptions
TEST_CATEGORY_UNIT="Unit tests for individual components"
TEST_CATEGORY_INTEGRATION="Integration tests for complete workflows"
TEST_CATEGORY_PERFORMANCE="Performance and resource usage tests"
TEST_CATEGORY_SECURITY="Security configuration validation tests"
TEST_CATEGORY_COMPATIBILITY="Cross-platform and version compatibility tests"
TEST_CATEGORY_REGRESSION="Regression tests to prevent known issues"

# Initialize testing framework
init_test_framework() {
    mkdir -p "$TEST_LOG_DIR"
    
    # Initialize test results file
    cat > "$TEST_RESULTS_FILE" << EOF
{
  "test_session_id": "$TEST_SESSION_ID",
  "start_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "test_framework_version": "3.0",
  "environment": {
    "os_version": "$(sw_vers -productVersion)",
    "hardware": "$(system_profiler SPHardwareDataType | grep 'Model Identifier' | awk '{print $3}' || echo 'unknown')",
    "working_directory": "$(pwd)"
  },
  "test_categories": {},
  "test_results": [],
  "summary": {
    "total_tests": 0,
    "passed": 0,
    "failed": 0,
    "skipped": 0,
    "duration_seconds": 0
  }
}
EOF
    
    log_test "INFO" "Test framework initialized for session $TEST_SESSION_ID"
}

# Logging function for tests
log_test() {
    local level="$1"
    local message="$2"
    local test_name="${3:-}"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Console output with colors
    case "$level" in
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        INFO) echo -e "${BLUE}[INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        DEBUG) echo -e "${CYAN}[DEBUG]${NC} $message" ;;
        FAIL) echo -e "${RED}[FAIL]${NC} $message" ;;
        PASS) echo -e "${GREEN}[PASS]${NC} $message" ;;
        SKIP) echo -e "${YELLOW}[SKIP]${NC} $message" ;;
    esac
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$TEST_LOG_DIR/test-framework.log"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [ "$expected" = "$actual" ]; then
        log_test "PASS" "$test_name: Expected '$expected', got '$actual'"
        return 0
    else
        log_test "FAIL" "$test_name: Expected '$expected', but got '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [ "$not_expected" != "$actual" ]; then
        log_test "PASS" "$test_name: Value '$actual' is not equal to '$not_expected'"
        return 0
    else
        log_test "FAIL" "$test_name: Value should not be '$not_expected' but it was"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local test_name="$2"
    
    if [ -f "$file_path" ]; then
        log_test "PASS" "$test_name: File '$file_path' exists"
        return 0
    else
        log_test "FAIL" "$test_name: File '$file_path' does not exist"
        return 1
    fi
}

assert_command_exists() {
    local command="$1"
    local test_name="$2"
    
    if command -v "$command" >/dev/null 2>&1; then
        log_test "PASS" "$test_name: Command '$command' is available"
        return 0
    else
        log_test "FAIL" "$test_name: Command '$command' is not available"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local test_name="$2"
    local timeout="${3:-$TIMEOUT_SECONDS}"
    
    # Check if timeout command is available
    if [ -z "$TIMEOUT_CMD" ]; then
        log_test "WARN" "$test_name: No timeout command available (timeout/gtimeout), running without timeout"
        if bash -c "$command" >/dev/null 2>&1; then
            log_test "PASS" "$test_name: Command '$command' executed successfully"
            return 0
        else
            log_test "FAIL" "$test_name: Command '$command' failed"
            return 1
        fi
    else
        if "$TIMEOUT_CMD" "$timeout" bash -c "$command" >/dev/null 2>&1; then
            log_test "PASS" "$test_name: Command '$command' executed successfully"
            return 0
        else
            log_test "FAIL" "$test_name: Command '$command' failed or timed out"
            return 1
        fi
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        log_test "PASS" "$test_name: String contains '$needle'"
        return 0
    else
        log_test "FAIL" "$test_name: String does not contain '$needle'"
        return 1
    fi
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    local category="${3:-unit}"
    local description="${4:-No description}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    local start_time=$(date +%s)
    
    log_test "INFO" "Running test: $test_name ($category)"
    
    local test_result="unknown"
    local error_message=""
    
    if "$test_function"; then
        test_result="passed"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_test "PASS" "$test_name completed successfully"
    else
        test_result="failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_test "FAIL" "$test_name failed"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Record test result in JSON file
    if command -v jq >/dev/null 2>&1; then
        local test_entry=$(jq -n \
            --arg name "$test_name" \
            --arg result "$test_result" \
            --arg category "$category" \
            --arg description "$description" \
            --arg duration "$duration" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
                "name": $name,
                "result": $result,
                "category": $category,
                "description": $description,
                "duration_seconds": ($duration | tonumber),
                "timestamp": $timestamp
            }')
        
        jq --argjson test "$test_entry" \
           '.test_results += [$test]' \
           "$TEST_RESULTS_FILE" > "$TEST_RESULTS_FILE.tmp" && mv "$TEST_RESULTS_FILE.tmp" "$TEST_RESULTS_FILE"
    fi
}

# Skip test with reason
skip_test() {
    local test_name="$1"
    local reason="$2"
    local category="${3:-unit}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    
    log_test "SKIP" "$test_name: $reason"
    
    # Record skipped test
    if command -v jq >/dev/null 2>&1; then
        local test_entry=$(jq -n \
            --arg name "$test_name" \
            --arg reason "$reason" \
            --arg category "$category" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
                "name": $name,
                "result": "skipped",
                "category": $category,
                "skip_reason": $reason,
                "timestamp": $timestamp
            }')
        
        jq --argjson test "$test_entry" \
           '.test_results += [$test]' \
           "$TEST_RESULTS_FILE" > "$TEST_RESULTS_FILE.tmp" && mv "$TEST_RESULTS_FILE.tmp" "$TEST_RESULTS_FILE"
    fi
}

# Unit tests for core components
test_validate_setup_script() {
    assert_file_exists "./validate-setup.sh" "Validate setup script exists"
    assert_command_success "bash ./validate-setup.sh --help" "Validate setup script shows help"
    assert_command_success "bash -n ./validate-setup.sh" "Validate setup script syntax check"
}

test_error_recovery_script() {
    assert_file_exists "./scripts/error-recovery.sh" "Error recovery script exists"
    assert_command_success "bash ./scripts/error-recovery.sh diagnostics" "Error recovery diagnostics mode"
    assert_command_success "bash -n ./scripts/error-recovery.sh" "Error recovery script syntax check"
}

test_build_monitor_script() {
    assert_file_exists "./scripts/build-monitor.sh" "Build monitor script exists"
    assert_command_success "bash ./scripts/build-monitor.sh init" "Build monitor initialization"
    assert_command_success "bash -n ./scripts/build-monitor.sh" "Build monitor script syntax check"
}

test_packer_manifests() {
    local manifests=("vm-ipsw-1password.pkr.hcl" "vm-container-1password.pkr.hcl" "vm-vanilla-custom-user.pkr.hcl")
    
    for manifest in "${manifests[@]}"; do
        if [ -f "$manifest" ]; then
            assert_file_exists "$manifest" "Packer manifest $manifest exists"
            assert_command_success "packer validate -syntax-only $manifest" "Packer manifest $manifest syntax validation" 10
        else
            skip_test "packer_manifest_$manifest" "Manifest file not found"
        fi
    done
}

test_1password_cli_availability() {
    if command -v op >/dev/null 2>&1; then
        assert_command_exists "op" "1Password CLI is available"
        # Test 1Password CLI without requiring authentication for unit test
        assert_command_success "op --version" "1Password CLI version check"
    else
        skip_test "1password_cli" "1Password CLI not installed"
    fi
}

test_required_dependencies() {
    local deps=("packer" "tart" "jq" "ssh-keygen")
    
    for dep in "${deps[@]}"; do
        assert_command_exists "$dep" "Required dependency: $dep"
    done
}

test_configuration_system() {
    if [ -f "config/default.toml" ]; then
        assert_file_exists "config/default.toml" "Default configuration file exists"
        
        if [ -f "validate-config.py" ]; then
            assert_command_success "python3 validate-config.py" "Configuration validation script"
        fi
    else
        skip_test "configuration_system" "Configuration files not found"
    fi
}

# Integration tests
test_full_validation_workflow() {
    log_test "INFO" "Running full validation workflow integration test"
    
    # Test with different validation modes
    assert_command_success "bash ./validate-setup.sh --silent" "Silent validation mode"
    assert_command_success "bash ./validate-setup.sh --verbose" "Verbose validation mode" 30
    
    # Test error recovery integration
    assert_command_success "bash ./scripts/error-recovery.sh full" "Full error recovery workflow" 60
}

test_monitoring_integration() {
    log_test "INFO" "Testing monitoring system integration"
    
    # Initialize monitoring
    assert_command_success "bash ./scripts/build-monitor.sh init" "Monitoring initialization"
    
    # Test monitoring functions
    assert_command_success "bash ./scripts/build-monitor.sh baseline" "Performance baseline creation"
    assert_command_success "bash ./scripts/build-monitor.sh alerts" "Alert system check"
    
    # Test session management
    assert_command_success "bash ./scripts/build-monitor.sh start integration test-manifest" "Start monitoring session"
    sleep 2
    assert_command_success "bash ./scripts/build-monitor.sh complete success" "Complete monitoring session"
}

# Performance tests
test_validation_performance() {
    log_test "INFO" "Testing validation script performance"
    
    local start_time=$(date +%s)
    bash ./validate-setup.sh --silent >/dev/null 2>&1 || true
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Validation should complete within reasonable time (30 seconds)
    if [ "$duration" -lt 30 ]; then
        log_test "PASS" "Validation performance: ${duration}s (under 30s threshold)"
        return 0
    else
        log_test "FAIL" "Validation performance: ${duration}s (over 30s threshold)"
        return 1
    fi
}

test_error_recovery_performance() {
    log_test "INFO" "Testing error recovery script performance"
    
    local start_time=$(date +%s)
    bash ./scripts/error-recovery.sh network >/dev/null 2>&1 || true
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Network recovery should complete within reasonable time
    if [ "$duration" -lt 15 ]; then
        log_test "PASS" "Error recovery performance: ${duration}s (under 15s threshold)"
        return 0
    else
        log_test "FAIL" "Error recovery performance: ${duration}s (over 15s threshold)"
        return 1
    fi
}

# Security tests
test_script_permissions() {
    local scripts=("validate-setup.sh" "scripts/error-recovery.sh" "scripts/build-monitor.sh")
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            local perms=$(stat -f "%A" "$script")
            if [ "$perms" = "755" ] || [ "$perms" = "644" ]; then
                log_test "PASS" "Script permissions for $script: $perms"
            else
                log_test "FAIL" "Script permissions for $script: $perms (should be 755 or 644)"
                return 1
            fi
        fi
    done
    
    return 0
}

test_no_hardcoded_secrets() {
    local files=("*.sh" "*.pkr.hcl" "*.py" "config/*.toml")
    local found_secrets=false
    
    for pattern in "${files[@]}"; do
        if ls $pattern >/dev/null 2>&1; then
            # Look for common secret patterns
            if grep -r -E "(password|secret|key).*['\"].*['\"]" $pattern 2>/dev/null | grep -v -E "(example|template|placeholder|default)" | grep -q .; then
                log_test "FAIL" "Potential hardcoded secrets found in files matching $pattern"
                found_secrets=true
            fi
        fi
    done
    
    if [ "$found_secrets" = false ]; then
        log_test "PASS" "No hardcoded secrets detected"
        return 0
    else
        return 1
    fi
}

# Generate comprehensive test report
generate_test_report() {
    local total_duration=$(($(date +%s) - $(date -d "$(jq -r '.start_time' "$TEST_RESULTS_FILE")" +%s)))
    
    # Update final summary
    if command -v jq >/dev/null 2>&1; then
        jq --arg total "$TESTS_RUN" \
           --arg passed "$TESTS_PASSED" \
           --arg failed "$TESTS_FAILED" \
           --arg skipped "$TESTS_SKIPPED" \
           --arg duration "$total_duration" \
           --arg end_time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.summary = {
             "total_tests": ($total | tonumber),
             "passed": ($passed | tonumber),
             "failed": ($failed | tonumber),
             "skipped": ($skipped | tonumber),
             "duration_seconds": ($duration | tonumber)
           } | .end_time = $end_time' \
           "$TEST_RESULTS_FILE" > "$TEST_RESULTS_FILE.tmp" && mv "$TEST_RESULTS_FILE.tmp" "$TEST_RESULTS_FILE"
    fi
    
    # Generate markdown report
    local report_file="$TEST_LOG_DIR/test-report-$(date +%Y%m%d-%H%M%S).md"
    
    {
        echo "# VM Builder Test Report"
        echo ""
        echo "**Test Session ID:** $TEST_SESSION_ID"
        echo "**Date:** $(date)"
        echo "**Duration:** ${total_duration}s"
        echo ""
        
        echo "## Summary"
        echo ""
        echo "- **Total Tests:** $TESTS_RUN"
        echo "- **Passed:** $TESTS_PASSED"
        echo "- **Failed:** $TESTS_FAILED"
        echo "- **Skipped:** $TESTS_SKIPPED"
        echo "- **Success Rate:** $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
        echo ""
        
        echo "## Test Categories"
        echo ""
        echo "- **unit:** $TEST_CATEGORY_UNIT"
        echo "- **integration:** $TEST_CATEGORY_INTEGRATION"
        echo "- **performance:** $TEST_CATEGORY_PERFORMANCE"
        echo "- **security:** $TEST_CATEGORY_SECURITY"
        echo "- **compatibility:** $TEST_CATEGORY_COMPATIBILITY"
        echo "- **regression:** $TEST_CATEGORY_REGRESSION"
        echo ""
        
        echo "## Detailed Results"
        echo ""
        if command -v jq >/dev/null 2>&1; then
            jq -r '.test_results[] | "- **\(.name)** (\(.category)): \(.result) (\(.duration_seconds // 0)s)"' "$TEST_RESULTS_FILE"
        fi
        echo ""
        
        echo "## Test Data"
        echo ""
        echo "- **Results File:** $TEST_RESULTS_FILE"
        echo "- **Log Directory:** $TEST_LOG_DIR"
        echo ""
    } > "$report_file"
    
    log_test "INFO" "Test report generated: $report_file"
    
    # Print summary to console
    echo ""
    echo -e "${CYAN}=== Test Summary ===${NC}"
    echo -e "${CYAN}Total Tests:${NC} $TESTS_RUN"
    echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}Failed:${NC} $TESTS_FAILED"
    echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo -e "${CYAN}Success Rate:${NC} $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
    echo -e "${CYAN}Duration:${NC} ${total_duration}s"
    echo -e "${CYAN}Report:${NC} $report_file"
    echo ""
}

# Main test suite execution
run_test_suite() {
    local test_type="${1:-all}"
    
    init_test_framework
    log_test "INFO" "Starting test suite execution: $test_type"
    
    case "$test_type" in
        "unit")
            log_test "INFO" "Running unit tests..."
            run_test "validate_setup_script" "test_validate_setup_script" "unit" "Validate setup script functionality"
            run_test "error_recovery_script" "test_error_recovery_script" "unit" "Error recovery script functionality"
            run_test "build_monitor_script" "test_build_monitor_script" "unit" "Build monitor script functionality"
            run_test "packer_manifests" "test_packer_manifests" "unit" "Packer manifest validation"
            run_test "1password_cli" "test_1password_cli_availability" "unit" "1Password CLI availability"
            run_test "required_dependencies" "test_required_dependencies" "unit" "Required system dependencies"
            run_test "configuration_system" "test_configuration_system" "unit" "Configuration system validation"
            ;;
        "integration")
            log_test "INFO" "Running integration tests..."
            run_test "full_validation_workflow" "test_full_validation_workflow" "integration" "Complete validation workflow"
            run_test "monitoring_integration" "test_monitoring_integration" "integration" "Monitoring system integration"
            ;;
        "performance")
            log_test "INFO" "Running performance tests..."
            run_test "validation_performance" "test_validation_performance" "performance" "Validation script performance"
            run_test "error_recovery_performance" "test_error_recovery_performance" "performance" "Error recovery performance"
            ;;
        "security")
            log_test "INFO" "Running security tests..."
            run_test "script_permissions" "test_script_permissions" "security" "Script file permissions"
            run_test "no_hardcoded_secrets" "test_no_hardcoded_secrets" "security" "No hardcoded secrets"
            ;;
        "all")
            log_test "INFO" "Running all test categories..."
            # Unit tests
            log_test "INFO" "Running unit tests..."
            run_test "validate_setup_script" "test_validate_setup_script" "unit" "Validate setup script functionality"
            run_test "error_recovery_script" "test_error_recovery_script" "unit" "Error recovery script functionality"
            run_test "build_monitor_script" "test_build_monitor_script" "unit" "Build monitor script functionality"
            run_test "packer_manifests" "test_packer_manifests" "unit" "Packer manifest validation"
            run_test "1password_cli" "test_1password_cli_availability" "unit" "1Password CLI availability"
            run_test "required_dependencies" "test_required_dependencies" "unit" "Required system dependencies"
            run_test "configuration_system" "test_configuration_system" "unit" "Configuration system validation"
            
            # Integration tests
            log_test "INFO" "Running integration tests..."
            run_test "full_validation_workflow" "test_full_validation_workflow" "integration" "Complete validation workflow"
            run_test "monitoring_integration" "test_monitoring_integration" "integration" "Monitoring system integration"
            
            # Performance tests
            log_test "INFO" "Running performance tests..."
            run_test "validation_performance" "test_validation_performance" "performance" "Validation script performance"
            run_test "error_recovery_performance" "test_error_recovery_performance" "performance" "Error recovery performance"
            
            # Security tests
            log_test "INFO" "Running security tests..."
            run_test "script_permissions" "test_script_permissions" "security" "Script file permissions"
            run_test "no_hardcoded_secrets" "test_no_hardcoded_secrets" "security" "No hardcoded secrets"
            ;;
        *)
            log_test "ERROR" "Unknown test type: $test_type"
            return 1
            ;;
    esac
    
    generate_test_report
    
    # Return appropriate exit code
    if [ "$TESTS_FAILED" -eq 0 ]; then
        log_test "SUCCESS" "All tests passed!"
        return 0
    else
        log_test "ERROR" "$TESTS_FAILED test(s) failed"
        return 1
    fi
}

# Main function
main() {
    local action="${1:-run}"
    
    case "$action" in
        "run")
            local test_type="${2:-all}"
            run_test_suite "$test_type"
            ;;
        "init")
            init_test_framework
            ;;
        "report")
            generate_test_report
            ;;
        *)
            echo "Usage: $0 {run|init|report} [test_type]"
            echo ""
            echo "Actions:"
            echo "  run [TYPE]    - Run test suite (TYPE: all, unit, integration, performance, security)"
            echo "  init          - Initialize test framework"
            echo "  report        - Generate test report"
            echo ""
            echo "Test Types:"
            echo "  all           - Run all test categories"
            echo "  unit          - Run unit tests only"
            echo "  integration   - Run integration tests only"
            echo "  performance   - Run performance tests only"
            echo "  security      - Run security tests only"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi