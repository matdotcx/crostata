#!/bin/bash
# VM Builder Monitoring and Observability Framework - Phase 3
# Provides comprehensive build monitoring, logging, and performance tracking

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
MONITOR_LOG_DIR="/tmp/vm-builder-monitoring"
BUILD_LOG_FILE="$MONITOR_LOG_DIR/build-session-$(date +%Y%m%d-%H%M%S).log"
METRICS_FILE="$MONITOR_LOG_DIR/metrics.json"
ALERT_LOG="$MONITOR_LOG_DIR/alerts.log"
SESSION_ID=$(date +%s%N | cut -c1-13)
MONITORING_INTERVAL=5
MAX_LOG_SIZE_MB=100
PERFORMANCE_BASELINE_FILE="$MONITOR_LOG_DIR/performance-baseline.json"

# Performance tracking variables
BUILD_START_TIME="0"
LAST_CHECKPOINT_TIME="0"
TOTAL_BUILD_TIME="0"
NETWORK_BYTES_DOWNLOADED="0"
DISK_SPACE_USED="0"
MEMORY_PEAK_USAGE="0"
CPU_AVERAGE_USAGE="0"

# Build phases
PHASE_INITIALIZATION="pending"
PHASE_DEPENDENCY_CHECK="pending"
PHASE_PACKER_INIT="pending"
PHASE_VM_CREATION="pending"
PHASE_PROVISIONING="pending"
PHASE_FINALIZATION="pending"

# Initialize monitoring system
init_monitoring() {
    mkdir -p "$MONITOR_LOG_DIR"
    
    # Initialize metrics file if it doesn't exist
    if [ ! -f "$METRICS_FILE" ]; then
        cat > "$METRICS_FILE" << 'EOF'
{
  "build_sessions": {},
  "global_metrics": {
    "total_builds": 0,
    "successful_builds": 0,
    "failed_builds": 0,
    "average_build_time_seconds": 0,
    "last_build_timestamp": null
  },
  "performance_trends": {
    "build_times": [],
    "resource_usage": []
  },
  "alerts": {
    "active_alerts": [],
    "alert_history": []
  }
}
EOF
    fi
    
    # Initialize performance baseline if it doesn't exist
    if [ ! -f "$PERFORMANCE_BASELINE_FILE" ]; then
        create_performance_baseline
    fi
    
    log_metric "INFO" "Monitoring system initialized for session $SESSION_ID"
}

# Logging with structured data
log_metric() {
    local level="$1"
    local message="$2"
    local metadata="${3:-}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Console output with colors
    case "$level" in
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        INFO) echo -e "${BLUE}[INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        DEBUG) echo -e "${CYAN}[DEBUG]${NC} $message" ;;
        PERF) echo -e "${MAGENTA}[PERF]${NC} $message" ;;
    esac
    
    # Structured logging to file
    local log_entry
    if [ -n "$metadata" ]; then
        log_entry="{\"timestamp\": \"$timestamp\", \"level\": \"$level\", \"session_id\": \"$SESSION_ID\", \"message\": \"$message\", \"metadata\": $metadata}"
    else
        log_entry="{\"timestamp\": \"$timestamp\", \"level\": \"$level\", \"session_id\": \"$SESSION_ID\", \"message\": \"$message\"}"
    fi
    
    echo "$log_entry" >> "$BUILD_LOG_FILE"
    
    # Rotate log if it gets too large
    if [ -f "$BUILD_LOG_FILE" ]; then
        local log_size_mb=$(( $(wc -c < "$BUILD_LOG_FILE") / 1024 / 1024 ))
        if [ "$log_size_mb" -gt "$MAX_LOG_SIZE_MB" ]; then
            mv "$BUILD_LOG_FILE" "${BUILD_LOG_FILE}.$(date +%s)"
            log_metric "INFO" "Log file rotated due to size (${log_size_mb}MB)"
        fi
    fi
}

# Performance baseline creation
create_performance_baseline() {
    log_metric "INFO" "Creating performance baseline..."
    
    local cpu_cores=$(sysctl -n hw.ncpu)
    local memory_gb=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    local disk_speed=$(dd if=/dev/zero of=/tmp/baseline_test bs=1m count=100 2>&1 | grep -o '[0-9.]\+ MB/s' | head -1 || echo "unknown")
    
    cat > "$PERFORMANCE_BASELINE_FILE" << EOF
{
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "system_specs": {
    "cpu_cores": $cpu_cores,
    "memory_gb": $memory_gb,
    "disk_speed": "$disk_speed",
    "os_version": "$(sw_vers -productVersion)",
    "hardware_model": "$(system_profiler SPHardwareDataType | grep 'Model Identifier' | awk '{print $3}' || echo "unknown")"
  },
  "expected_performance": {
    "typical_build_time_minutes": 15,
    "max_memory_usage_percent": 70,
    "max_cpu_usage_percent": 80,
    "min_disk_speed_mbps": 50
  }
}
EOF
    
    rm -f /tmp/baseline_test 2>/dev/null || true
    log_metric "PERF" "Performance baseline created with $cpu_cores cores, ${memory_gb}GB RAM"
}

# Build phase tracking
start_build_phase() {
    local phase="$1"
    local description="${2:-}"
    
    case "$phase" in
        "initialization") PHASE_INITIALIZATION="in_progress" ;;
        "dependency_check") PHASE_DEPENDENCY_CHECK="in_progress" ;;
        "packer_init") PHASE_PACKER_INIT="in_progress" ;;
        "vm_creation") PHASE_VM_CREATION="in_progress" ;;
        "provisioning") PHASE_PROVISIONING="in_progress" ;;
        "finalization") PHASE_FINALIZATION="in_progress" ;;
    esac
    
    LAST_CHECKPOINT_TIME=$(date +%s)
    
    log_metric "INFO" "Started build phase: $phase" "{\"phase\": \"$phase\", \"description\": \"$description\"}"
    
    # Update metrics file
    if command -v jq >/dev/null 2>&1; then
        jq --arg sid "$SESSION_ID" \
           --arg phase "$phase" \
           --arg status "in_progress" \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.build_sessions[$sid].phases[$phase] = {"status": $status, "start_time": $ts}' \
           "$METRICS_FILE" > "$METRICS_FILE.tmp" && mv "$METRICS_FILE.tmp" "$METRICS_FILE"
    fi
}

complete_build_phase() {
    local phase="$1"
    local status="${2:-success}"
    local details="${3:-}"
    
    case "$phase" in
        "initialization") PHASE_INITIALIZATION="$status" ;;
        "dependency_check") PHASE_DEPENDENCY_CHECK="$status" ;;
        "packer_init") PHASE_PACKER_INIT="$status" ;;
        "vm_creation") PHASE_VM_CREATION="$status" ;;
        "provisioning") PHASE_PROVISIONING="$status" ;;
        "finalization") PHASE_FINALIZATION="$status" ;;
    esac
    
    local current_time=$(date +%s)
    local phase_duration=$((current_time - LAST_CHECKPOINT_TIME))
    
    log_metric "SUCCESS" "Completed build phase: $phase (${phase_duration}s)" "{\"phase\": \"$phase\", \"duration_seconds\": $phase_duration, \"status\": \"$status\"}"
    
    # Update metrics file
    if command -v jq >/dev/null 2>&1; then
        jq --arg sid "$SESSION_ID" \
           --arg phase "$phase" \
           --arg status "$status" \
           --arg duration "$phase_duration" \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.build_sessions[$sid].phases[$phase] += {"status": $status, "end_time": $ts, "duration_seconds": ($duration | tonumber)}' \
           "$METRICS_FILE" > "$METRICS_FILE.tmp" && mv "$METRICS_FILE.tmp" "$METRICS_FILE"
    fi
}

# Real-time system monitoring
monitor_system_resources() {
    local monitor_duration="${1:-60}"  # Monitor for 60 seconds by default
    local samples=0
    local cpu_total=0
    local memory_peak=0
    
    log_metric "DEBUG" "Starting system resource monitoring for ${monitor_duration}s"
    
    local end_time=$(($(date +%s) + monitor_duration))
    
    while [ $(date +%s) -lt $end_time ]; do
        # CPU usage
        local cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo "0")
        cpu_total=$(echo "$cpu_total + $cpu_usage" | bc -l 2>/dev/null || echo "$cpu_total")
        
        # Memory usage
        local memory_info=$(vm_stat | grep -E "(free|active|inactive|wired)" | awk '{print $3}' | sed 's/\.//')
        local memory_used=0
        for mem in $memory_info; do
            memory_used=$((memory_used + mem))
        done
        memory_used=$((memory_used * 4096 / 1024 / 1024))  # Convert to MB
        
        if [ "$memory_used" -gt "$memory_peak" ]; then
            memory_peak=$memory_used
        fi
        
        samples=$((samples + 1))
        sleep "$MONITORING_INTERVAL"
    done
    
    # Calculate averages
    local cpu_average
    if [ "$samples" -gt 0 ]; then
        cpu_average=$(echo "scale=2; $cpu_total / $samples" | bc -l 2>/dev/null || echo "0")
    else
        cpu_average="0"
    fi
    
    CPU_AVERAGE_USAGE="$cpu_average"
    MEMORY_PEAK_USAGE="$memory_peak"
    
    log_metric "PERF" "Resource monitoring completed: CPU avg ${cpu_average}%, Memory peak ${memory_peak}MB" \
        "{\"cpu_average_percent\": $cpu_average, \"memory_peak_mb\": $memory_peak, \"samples\": $samples}"
}

# Disk usage monitoring
monitor_disk_usage() {
    local initial_usage=$(df / | tail -1 | awk '{print $3}')
    
    # Store initial disk usage
    PERFORMANCE_COUNTERS["disk_initial_usage"]="$initial_usage"
    
    # Function to get current disk usage difference
    get_disk_usage_delta() {
        local current_usage=$(df / | tail -1 | awk '{print $3}')
        local delta=$((current_usage - initial_usage))
        echo "$delta"
    }
    
    log_metric "DEBUG" "Disk monitoring initialized, baseline: ${initial_usage}KB"
}

# Network monitoring
monitor_network_activity() {
    local interface=$(route get default | grep interface | awk '{print $2}')
    local initial_bytes=$(netstat -I "$interface" | tail -1 | awk '{print $7}' || echo "0")
    
    PERFORMANCE_COUNTERS["network_initial_bytes"]="$initial_bytes"
    
    # Function to get network bytes downloaded
    get_network_delta() {
        local current_bytes=$(netstat -I "$interface" | tail -1 | awk '{print $7}' || echo "0")
        local delta=$((current_bytes - initial_bytes))
        echo "$delta"
    }
    
    log_metric "DEBUG" "Network monitoring initialized on interface $interface, baseline: ${initial_bytes} bytes"
}

# Alert system
check_performance_alerts() {
    local cpu_threshold=85
    local memory_threshold=90
    local disk_threshold=95
    
    # Check CPU usage
    local current_cpu=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo "0")
    if (( $(echo "$current_cpu > $cpu_threshold" | bc -l 2>/dev/null || echo "0") )); then
        create_alert "HIGH_CPU" "CPU usage is ${current_cpu}% (threshold: ${cpu_threshold}%)"
    fi
    
    # Check memory usage
    local memory_info=$(vm_stat | head -5 | tail -4 | awk '{print $3}' | sed 's/\.//')
    local total_memory=0
    for mem in $memory_info; do
        total_memory=$((total_memory + mem))
    done
    local total_memory_mb=$((total_memory * 4096 / 1024 / 1024))
    local system_memory_mb=$(($(sysctl -n hw.memsize) / 1024 / 1024))
    local memory_percent=$((total_memory_mb * 100 / system_memory_mb))
    
    if [ "$memory_percent" -gt "$memory_threshold" ]; then
        create_alert "HIGH_MEMORY" "Memory usage is ${memory_percent}% (threshold: ${memory_threshold}%)"
    fi
    
    # Check disk usage
    local disk_percent=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_percent" -gt "$disk_threshold" ]; then
        create_alert "HIGH_DISK" "Disk usage is ${disk_percent}% (threshold: ${disk_threshold}%)"
    fi
}

create_alert() {
    local alert_type="$1"
    local message="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    log_metric "WARN" "ALERT: $alert_type - $message"
    
    local alert_entry="{\"timestamp\": \"$timestamp\", \"type\": \"$alert_type\", \"message\": \"$message\", \"session_id\": \"$SESSION_ID\"}"
    echo "$alert_entry" >> "$ALERT_LOG"
    
    # Add to metrics file if jq is available
    if command -v jq >/dev/null 2>&1; then
        jq --argjson alert "$alert_entry" \
           '.alerts.active_alerts += [$alert] | .alerts.alert_history += [$alert]' \
           "$METRICS_FILE" > "$METRICS_FILE.tmp" && mv "$METRICS_FILE.tmp" "$METRICS_FILE"
    fi
}

# Build session initialization
start_build_session() {
    local build_type="$1"
    local manifest_file="$2"
    
    BUILD_START_TIME=$(date +%s)
    
    log_metric "INFO" "Starting build session" "{\"build_type\": \"$build_type\", \"manifest\": \"$manifest_file\"}"
    
    # Initialize monitoring
    init_monitoring
    monitor_disk_usage
    monitor_network_activity
    
    # Start background resource monitoring
    monitor_system_resources 3600 &  # Monitor for up to 1 hour
    local monitor_pid=$!
    echo "$monitor_pid" > "$MONITOR_LOG_DIR/monitor_pid_$SESSION_ID"
    
    # Update metrics file
    if command -v jq >/dev/null 2>&1; then
        jq --arg sid "$SESSION_ID" \
           --arg type "$build_type" \
           --arg manifest "$manifest_file" \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.build_sessions[$sid] = {
             "build_type": $type,
             "manifest_file": $manifest,
             "start_time": $ts,
             "status": "in_progress",
             "phases": {}
           } | .global_metrics.total_builds += 1' \
           "$METRICS_FILE" > "$METRICS_FILE.tmp" && mv "$METRICS_FILE.tmp" "$METRICS_FILE"
    fi
    
    start_build_phase "initialization" "Build session initialization"
}

# Build session completion
complete_build_session() {
    local status="$1"
    local error_message="${2:-}"
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - BUILD_START_TIME))
    TOTAL_BUILD_TIME="$total_duration"
    
    # Stop background monitoring
    if [ -f "$MONITOR_LOG_DIR/monitor_pid_$SESSION_ID" ]; then
        local monitor_pid=$(cat "$MONITOR_LOG_DIR/monitor_pid_$SESSION_ID")
        kill "$monitor_pid" 2>/dev/null || true
        rm -f "$MONITOR_LOG_DIR/monitor_pid_$SESSION_ID"
    fi
    
    # Calculate final metrics
    local disk_used=$(get_disk_usage_delta 2>/dev/null || echo "0")
    local network_downloaded=$(get_network_delta 2>/dev/null || echo "0")
    
    DISK_SPACE_USED="$disk_used"
    NETWORK_BYTES_DOWNLOADED="$network_downloaded"
    
    log_metric "INFO" "Build session completed with status: $status" \
        "{\"total_duration_seconds\": $total_duration, \"disk_used_kb\": $disk_used, \"network_downloaded_bytes\": $network_downloaded}"
    
    # Update metrics file
    if command -v jq >/dev/null 2>&1; then
        local metric_update=""
        if [ "$status" = "success" ]; then
            metric_update='.global_metrics.successful_builds += 1'
        else
            metric_update='.global_metrics.failed_builds += 1'
        fi
        
        jq --arg sid "$SESSION_ID" \
           --arg status "$status" \
           --arg duration "$total_duration" \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg error "${error_message:-null}" \
           --arg cpu_avg "$CPU_AVERAGE_USAGE" \
           --arg mem_peak "$MEMORY_PEAK_USAGE" \
           --arg disk_used "$DISK_SPACE_USED" \
           --arg net_down "$NETWORK_BYTES_DOWNLOADED" \
           ".build_sessions[\$sid] += {
             \"status\": \$status,
             \"end_time\": \$ts,
             \"total_duration_seconds\": (\$duration | tonumber),
             \"error_message\": \$error,
             \"performance_counters\": {
               \"cpu_average_usage\": \$cpu_avg,
               \"memory_peak_usage\": \$mem_peak,
               \"disk_space_used\": \$disk_used,
               \"network_bytes_downloaded\": \$net_down
             }
           } | $metric_update | .global_metrics.last_build_timestamp = \$ts" \
           "$METRICS_FILE" > "$METRICS_FILE.tmp" && mv "$METRICS_FILE.tmp" "$METRICS_FILE"
    fi
    
    generate_session_report
}

# Generate comprehensive session report
generate_session_report() {
    local report_file="$MONITOR_LOG_DIR/session-report-$SESSION_ID.md"
    
    {
        echo "# VM Build Session Report"
        echo ""
        echo "**Session ID:** $SESSION_ID"
        echo "**Date:** $(date)"
        echo "**Total Duration:** ${TOTAL_BUILD_TIME}s"
        echo ""
        
        echo "## Build Phases"
        echo ""
        echo "- **initialization:** $PHASE_INITIALIZATION"
        echo "- **dependency_check:** $PHASE_DEPENDENCY_CHECK"
        echo "- **packer_init:** $PHASE_PACKER_INIT"
        echo "- **vm_creation:** $PHASE_VM_CREATION"
        echo "- **provisioning:** $PHASE_PROVISIONING"
        echo "- **finalization:** $PHASE_FINALIZATION"
        echo ""
        
        echo "## Performance Metrics"
        echo ""
        echo "- **CPU Average Usage:** ${CPU_AVERAGE_USAGE}%"
        echo "- **Memory Peak Usage:** ${MEMORY_PEAK_USAGE}MB"
        echo "- **Disk Space Used:** ${DISK_SPACE_USED}KB"
        echo "- **Network Downloaded:** ${NETWORK_BYTES_DOWNLOADED} bytes"
        echo ""
        
        echo "## Logs and Data"
        echo ""
        echo "- **Build Log:** $BUILD_LOG_FILE"
        echo "- **Metrics File:** $METRICS_FILE"
        echo "- **Alert Log:** $ALERT_LOG"
        echo ""
        
        if [ -f "$ALERT_LOG" ] && [ -s "$ALERT_LOG" ]; then
            echo "## Alerts Generated"
            echo ""
            echo '```json'
            cat "$ALERT_LOG"
            echo '```'
        fi
    } > "$report_file"
    
    log_metric "INFO" "Session report generated: $report_file"
}

# Performance comparison with baseline
compare_with_baseline() {
    if [ ! -f "$PERFORMANCE_BASELINE_FILE" ]; then
        log_metric "WARN" "No performance baseline found, skipping comparison"
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_metric "WARN" "jq not available, skipping baseline comparison"
        return 1
    fi
    
    local baseline_build_time=$(jq -r '.expected_performance.typical_build_time_minutes * 60' "$PERFORMANCE_BASELINE_FILE")
    local actual_build_time="$TOTAL_BUILD_TIME"
    
    if [ -n "$actual_build_time" ] && [ -n "$baseline_build_time" ]; then
        local performance_ratio=$(echo "scale=2; $actual_build_time / $baseline_build_time" | bc -l)
        
        if (( $(echo "$performance_ratio > 1.5" | bc -l) )); then
            create_alert "SLOW_BUILD" "Build took ${actual_build_time}s, expected around ${baseline_build_time}s (ratio: $performance_ratio)"
        elif (( $(echo "$performance_ratio < 0.7" | bc -l) )); then
            log_metric "SUCCESS" "Build completed faster than expected (ratio: $performance_ratio)"
        else
            log_metric "INFO" "Build performance within expected range (ratio: $performance_ratio)"
        fi
    fi
}

# Main monitoring functions for external use
monitor_packer_build() {
    local manifest_file="$1"
    local build_type="${2:-unknown}"
    
    start_build_session "$build_type" "$manifest_file"
    
    # This would be called by the main build script
    log_metric "INFO" "Packer build monitoring started for $manifest_file"
}

# Export functions for use by other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced, export functions
    export -f log_metric start_build_phase complete_build_phase
    export -f start_build_session complete_build_session
    export -f check_performance_alerts create_alert
    export -f monitor_system_resources compare_with_baseline
fi

# Main function for direct script execution
main() {
    local action="$1"
    shift
    
    case "$action" in
        "init")
            init_monitoring ;;
        "start")
            local build_type="${1:-manual}"
            local manifest="${2:-unknown}"
            start_build_session "$build_type" "$manifest" ;;
        "complete")
            local status="${1:-success}"
            local error="${2:-}"
            complete_build_session "$status" "$error" ;;
        "monitor")
            local duration="${1:-60}"
            monitor_system_resources "$duration" ;;
        "alerts")
            check_performance_alerts ;;
        "report")
            generate_session_report ;;
        "baseline")
            create_performance_baseline ;;
        *)
            echo "Usage: $0 {init|start|complete|monitor|alerts|report|baseline}"
            echo "  init                    - Initialize monitoring system"
            echo "  start BUILD_TYPE FILE   - Start build session monitoring"
            echo "  complete STATUS [ERROR] - Complete build session"
            echo "  monitor [DURATION]      - Monitor system resources"
            echo "  alerts                  - Check for performance alerts"
            echo "  report                  - Generate session report"
            echo "  baseline                - Create performance baseline"
            exit 1 ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi