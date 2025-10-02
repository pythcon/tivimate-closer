#!/bin/bash

# TiviMate Closer - Auto-close TiviMate on Android TV after inactivity
# Supports both single-run and continuous service mode

# Check for ADB
command -v adb >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "ERROR: ADB not found on system. Please install android-tools-adb"
    exit 1
fi

# Function to convert human-readable message to ADB format
convert_message_to_adb_format() {
    local msg="$1"
    # Check if message already contains %s (pre-formatted)
    if [[ "$msg" == *"%s"* ]]; then
        echo "$msg"
        return
    fi
    # Replace spaces with %s
    msg="${msg// /%s}"
    # Escape special characters for ADB input - most common ones
    msg="${msg//(/\\(}"
    msg="${msg//)/\\)}"
    msg="${msg//\?/\\?}"
    msg="${msg//!/\\!}"
    echo "$msg"
}

# Load environment variables with defaults
DURATION=${DURATION:-$((3 * 60 * 60))}  # 3 hours in seconds
WAIT_TIME=${WAIT_TIME:-30}
PACKAGE_NAME=${PACKAGE_NAME:-"ar.tvplayer.tv"}
WARNING_MESSAGE=${WARNING_MESSAGE:-"Are you still watching? (closing in 30 seconds)"}
TRACKFILE=${TRACKFILE:-"/tmp/onn_tracking.log"}
LOG_DIR=${LOG_DIR:-"/tmp"}
ADB_PORT=${ADB_PORT:-5555}
CHECK_INTERVAL=${CHECK_INTERVAL:-60}
SERVICE_MODE=${SERVICE_MODE:-false}
ACTIVITY_RESUME_PATTERN=${ACTIVITY_RESUME_PATTERN:-"mResumedActivity"}

# Convert warning message to ADB format if needed
WARNING_MESSAGE=$(convert_message_to_adb_format "$WARNING_MESSAGE")

# Function to get the current timestamp
timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Logger function - handles timestamp and file logging
log_message() {
    local level=$1
    local message=$2
    local logfile=${3:-""}

    local formatted_msg="[$(timestamp)] [$level] $message"

    if [ -n "$logfile" ]; then
        echo "$formatted_msg" | tee -a "$logfile"
    else
        echo "$formatted_msg"
    fi
}

# Helper function to convert seconds to human readable time
seconds_to_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# Function to check if the app is running
is_app_running() {
    local ip=$1
    adb -s "${ip}:${ADB_PORT}" shell dumpsys activity activities 2>/dev/null | grep "$ACTIVITY_RESUME_PATTERN" | grep -q "$PACKAGE_NAME"
}

# Function to check if the search overlay is open
is_search_open() {
    local ip=$1
    adb -s "${ip}:${ADB_PORT}" shell dumpsys input_method 2>/dev/null | grep -q 'mServedView=androidx.leanback.widget.SearchEditText'
}

# Function to display a message using key events
display_message() {
    local ip=$1
    local logfile=$2

    if ! is_search_open "$ip"; then
        # Simulate pressing the search button
        adb -s "${ip}:${ADB_PORT}" shell input keyevent KEYCODE_MENU 2>/dev/null
        sleep 1

        # Press OK
        adb -s "${ip}:${ADB_PORT}" shell input keyevent KEYCODE_ENTER 2>/dev/null
        sleep 1

        # Press the Right button
        adb -s "${ip}:${ADB_PORT}" shell input keyevent KEYCODE_DPAD_RIGHT 2>/dev/null
        sleep 1

        # Input the text message
        adb -s "${ip}:${ADB_PORT}" shell input text "${WARNING_MESSAGE}" 2>/dev/null
    fi

    # Wait for user interaction
    log_message "INFO" "Waiting ${WAIT_TIME} seconds for user interaction" "$logfile"
    sleep ${WAIT_TIME}

    # Check if the InputMethod window is still up
    if is_search_open "$ip"; then
        # If the InputMethod window is still up, press the Home button
        adb -s "${ip}:${ADB_PORT}" shell input keyevent KEYCODE_HOME 2>/dev/null
        log_message "ACTION" "Closing ${PACKAGE_NAME} on ${ip}" "$logfile"
    else
        log_message "INFO" "User interacted, keeping app open" "$logfile"
    fi
}

# Function to modify the trackfile
modify_trackfile() {
    local action=$1
    local ip=$2

    if [ "$action" == "create" ]; then
        echo "$ip $(timestamp)" > "$TRACKFILE"
    elif [ "$action" == "add" ]; then
        echo "$ip $(timestamp)" >> "$TRACKFILE"
    elif [ "$action" == "delete" ]; then
        # Remove the IP address entry from the trackfile
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "/$ip/d" "$TRACKFILE" 2>/dev/null
        else
            sed -i "/$ip/d" "$TRACKFILE" 2>/dev/null
        fi
    fi
}

# Function to check the trackfile and decide if the app needs to be turned off
check_trackfile() {
    local ip=$1
    local logfile=$2

    if [ -f "$TRACKFILE" ]; then
        last_check=$(grep "$ip" "$TRACKFILE" | awk '{print $2" "$3}')
        if [ -n "$last_check" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                last_check_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_check" +%s 2>/dev/null || echo "0")
            else
                last_check_timestamp=$(date -d "$last_check" +%s 2>/dev/null || echo "0")
            fi
            current_timestamp=$(date +%s)
            elapsed=$((current_timestamp - last_check_timestamp))

            if [ $elapsed -gt $DURATION ]; then
                log_message "WARN" "Time limit reached for ${ip} - showing warning message" "$logfile"
                modify_trackfile "delete" "$ip"
                return 0
            else
                local remaining=$((DURATION - elapsed))
                local time_left=$(seconds_to_time $remaining)
                local elapsed_time=$(seconds_to_time $elapsed)
                log_message "INFO" "App running for ${elapsed_time}, ${time_left} remaining until warning" "$logfile"
                return 1
            fi
        else
            log_message "INFO" "No entry for ${ip} in trackfile, starting timer" "$logfile"
            modify_trackfile "add" "$ip"
            return 1
        fi
    else
        log_message "INFO" "Trackfile not found, creating and starting timer for ${ip}" "$logfile"
        modify_trackfile "create" "$ip"
        return 1
    fi
}

# Function to handle the ADB connection and app check
process_device() {
    local ip=$1
    local logfile="${LOG_DIR}/onn_${ip}.log"

    log_message "INFO" "Connecting to ${ip}:${ADB_PORT}" "$logfile"

    # First disconnect any stale connections
    adb disconnect "${ip}:${ADB_PORT}" >/dev/null 2>&1

    # Connect to device
    connect_output=$(adb connect "${ip}:${ADB_PORT}" 2>&1)
    connect_status=$?

    # Check if connection failed due to authentication
    if echo "$connect_output" | grep -q "failed to authenticate"; then
        log_message "ERROR" "Authentication failed for ${ip}:${ADB_PORT}" "$logfile"
        log_message "ERROR" "Device needs to authorize this computer. Check the device screen." "$logfile"
        # Disconnect to clean up the failed connection
        adb disconnect "${ip}:${ADB_PORT}" >/dev/null 2>&1
        modify_trackfile "delete" "$ip"
        return 1
    fi

    sleep 2

    # Verify the device is properly connected and authorized
    device_state=$(adb -s "${ip}:${ADB_PORT}" get-state 2>&1)

    if [ "$device_state" = "device" ]; then
        log_message "SUCCESS" "Connected and authenticated to ${ip}" "$logfile"

        if is_app_running "$ip"; then
            log_message "INFO" "${PACKAGE_NAME} is running on ${ip}" "$logfile"

            if check_trackfile "$ip" "$logfile"; then
                display_message "$ip" "$logfile"
            fi
        else
            log_message "INFO" "${PACKAGE_NAME} is not running on ${ip}" "$logfile"
            if [ -f "$TRACKFILE" ]; then
                log_message "DEBUG" "Removing timer entry for ${ip}" "$logfile"
                modify_trackfile "delete" "$ip"
            fi
        fi

        adb disconnect "${ip}:${ADB_PORT}" >/dev/null 2>&1
        log_message "INFO" "Disconnected from ${ip}" "$logfile"
    else
        log_message "ERROR" "Failed to properly connect to ${ip}:${ADB_PORT}" "$logfile"
        log_message "ERROR" "Device state: $device_state" "$logfile"
        log_message "DEBUG" "Removing entry from trackfile" "$logfile"
        # Clean up any partial connection
        adb disconnect "${ip}:${ADB_PORT}" >/dev/null 2>&1
        modify_trackfile "delete" "$ip"
    fi
}

# Function to display help message
show_help() {
    cat <<EOF
TiviMate Closer - Auto-close TiviMate on Android TV after inactivity

Usage: $0 [OPTIONS] IP [IP...]

OPTIONS:
  -t duration      Duration to check if the app needs to be turned off (in seconds)
                   Default: ${DURATION} seconds ($(($DURATION / 3600)) hours)
                   Environment: DURATION

  -w wait          Duration to wait before checking user interaction (in seconds)
                   Default: ${WAIT_TIME} seconds
                   Environment: WAIT_TIME

  -i interval      Check interval for service mode (in seconds)
                   Default: ${CHECK_INTERVAL} seconds
                   Environment: CHECK_INTERVAL

  -s               Service mode - run continuously checking devices at intervals
                   Default: false (single run)
                   Environment: SERVICE_MODE=true

  -p port          ADB port to connect on
                   Default: ${ADB_PORT}
                   Environment: ADB_PORT

  -n package       Package name of the app to check
                   Default: ${PACKAGE_NAME}
                   Environment: PACKAGE_NAME

  -m message       Warning message to display
                   Default: "Are you still watching? (closing in 30 seconds)"
                   Supports human-readable format (auto-converted)
                   Or ADB format with %s for spaces
                   Environment: WARNING_MESSAGE

  -x trackfile     Track file path
                   Default: ${TRACKFILE}
                   Environment: TRACKFILE

  -d logdir        Log directory path
                   Default: ${LOG_DIR}
                   Environment: LOG_DIR

  -r pattern       Activity resume pattern for dumpsys (Android version dependent)
                   Default: ${ACTIVITY_RESUME_PATTERN}
                   Android 11-: "mResumedActivity"
                   Android 12+: "ResumedActivity"
                   Environment: ACTIVITY_RESUME_PATTERN

  -h               Show this help message

EXAMPLES:
  # Single run - check devices once
  $0 192.168.1.100 192.168.1.101

  # Custom duration (2 hours) and wait time
  $0 -t 7200 -w 30 192.168.1.100

  # Service mode - run continuously
  $0 -s -i 60 192.168.1.100 192.168.1.101

  # Service mode with custom settings
  $0 -s -i 30 -t 10800 -w 45 192.168.1.100

  # Using environment variables
  DURATION=7200 WAIT_TIME=45 SERVICE_MODE=true $0 192.168.1.100

  # Android 12+ device (use ResumedActivity instead of mResumedActivity)
  $0 -r ResumedActivity 192.168.1.100

EOF
    exit 0
}

# Parse command-line arguments
while getopts "t:w:i:d:n:m:x:p:r:sh" opt; do
    case ${opt} in
        t ) DURATION=$OPTARG ;;
        w ) WAIT_TIME=$OPTARG ;;
        i ) CHECK_INTERVAL=$OPTARG ;;
        d ) LOG_DIR=$OPTARG ;;
        n ) PACKAGE_NAME=$OPTARG ;;
        m ) WARNING_MESSAGE=$(convert_message_to_adb_format "$OPTARG") ;;
        x ) TRACKFILE=$OPTARG ;;
        p ) ADB_PORT=$OPTARG ;;
        r ) ACTIVITY_RESUME_PATTERN=$OPTARG ;;
        s ) SERVICE_MODE=true ;;
        h ) show_help ;;
        \? ) show_help ;;
    esac
done
shift $((OPTIND -1))

# Check if at least one IP address is provided
if [ "$#" -lt 1 ]; then
    echo "ERROR: At least one IP address is required."
    echo ""
    show_help
fi

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Store IP addresses in array
IP_ADDRESSES=("$@")

# Main execution
if [ "$SERVICE_MODE" = true ]; then
    # Service mode - run continuously
    echo "==================================================================="
    echo "TiviMate Closer Service Started at $(timestamp)"
    echo "==================================================================="
    echo "Configuration:"
    echo "  Device IPs: ${IP_ADDRESSES[*]}"
    echo "  Check Interval: ${CHECK_INTERVAL} seconds"
    echo "  Duration: ${DURATION} seconds ($(($DURATION / 3600)) hours)"
    echo "  Wait Time: ${WAIT_TIME} seconds"
    echo "  Package: ${PACKAGE_NAME}"
    echo "  Log Directory: ${LOG_DIR}"
    echo "==================================================================="
    echo ""

    # Handle signals for graceful shutdown
    trap 'echo ""; log_message "INFO" "Shutting down TiviMate Closer Service..."; exit 0' SIGTERM SIGINT

    # Main service loop
    while true; do
        log_message "INFO" "Starting check cycle..."

        for ip in "${IP_ADDRESSES[@]}"; do
            log_message "INFO" "Processing device: ${ip}"
            process_device "$ip"
        done

        log_message "INFO" "Check cycle complete. Sleeping for ${CHECK_INTERVAL} seconds..."
        echo ""
        sleep ${CHECK_INTERVAL}
    done
else
    # Single run mode - process each device once
    for ip in "${IP_ADDRESSES[@]}"; do
        process_device "$ip"
    done
fi
