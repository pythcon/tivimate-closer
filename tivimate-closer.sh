#!/bin/bash

command -v adb >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "ADB not found on system"
    exit 1
fi

# Default values
DURATION=$((3 * 60 * 60))  # 3 hours in seconds
WAIT=30
PACKAGE_NAME="ar.tvplayer.tv"
MESSAGE="Are%syou%sstill%swatching?%s\(closing%sin%s30%sseconds\)"
TRACKFILE="/tmp/onn_tracking.log"
PORT=5555

# Function to get the current timestamp
timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Function to check if the app is running
is_app_running() {
    adb shell dumpsys activity activities | grep "mResumedActivity" | grep -q "$PACKAGE_NAME"
}

# Function to check if the search overlay is open
is_search_open() {
    adb shell dumpsys input_method | grep -q 'mServedView=androidx.leanback.widget.SearchEditText'
}

# Function to display a message using key events
display_message() {
    if ! is_search_open; then
        # Simulate pressing the search button
        adb shell input keyevent KEYCODE_MENU
        sleep 1

        # Press OK
        adb shell input keyevent KEYCODE_ENTER
        sleep 1

        # Press the Right button
        adb shell input keyevent KEYCODE_DPAD_RIGHT
        sleep 1

        # Input the text message
        adb shell input text "${MESSAGE}"
    fi

    # Wait for WAIT seconds
    echo "($(timestamp)): Waiting ${WAIT} seconds for user interaction" | tee -a ${LOGFILE}
    sleep ${WAIT}

    # Check if the InputMethod window is still up
    if is_search_open; then
        # If the InputMethod window is still up, press the Home button
        adb shell input keyevent KEYCODE_HOME
        echo "($(timestamp)): Closing ${PACKAGE_NAME}" | tee -a ${LOGFILE}
    else
        echo "($(timestamp)): User interacted, ignoring close." | tee -a ${LOGFILE}
    fi
}

# Function to check the trackfile and decide if the app needs to be turned off
check_trackfile() {
    if [ -f "$TRACKFILE" ]; then
        last_check=$(grep "$IP_ADDRESS" "$TRACKFILE" | awk '{print $2" "$3}')
        if [ -n "$last_check" ]; then
            last_check_timestamp=$(date -d"$last_check" +%s)
            current_timestamp=$(date +%s)
            elapsed=$((current_timestamp - last_check_timestamp))
            if [ $elapsed -gt $DURATION ]; then
                echo "($(timestamp)): Elapsed time greater than duration, quiting ${PACKAGE_NAME}" | tee -a "$LOGFILE"
                # Remove the IP address entry from the trackfile
                sed -i "/$IP_ADDRESS/d" "$TRACKFILE"
                return 0
            else
                echo "($(timestamp)): Elapsed time less than duration, no action" | tee -a "$LOGFILE"
                return 1
            fi
        else
            echo "($(timestamp)): No entry for $IP_ADDRESS in trackfile, adding one now" | tee -a "$LOGFILE"
            echo "$IP_ADDRESS $(timestamp)" >> "$TRACKFILE"
            return 1
        fi
    else
        echo "($(timestamp)): Trackfile not found. Creating and adding entry for $IP_ADDRESS" | tee -a "$LOGFILE"
        echo "$IP_ADDRESS $(timestamp)" > "$TRACKFILE"
        return 1
    fi
}

# Function to handle the ADB connection and app check
process_device() {
    local IP_ADDRESS=$1

    printf "($(timestamp)): Connecting to $IP_ADDRESS:${PORT}\n" | tee -a "$LOGFILE"
    
    adb connect "$IP_ADDRESS:${PORT}" >/dev/null 2>&1
    
    if adb devices | grep -q "$IP_ADDRESS:${PORT}"; then
        echo "($(timestamp)): Successfully connected to $IP_ADDRESS" | tee -a "$LOGFILE"
        
        if is_app_running; then
            echo "($(timestamp)): ${PACKAGE_NAME} is running on $IP_ADDRESS. Checking trackfile..." | tee -a "$LOGFILE"
            
            if check_trackfile; then
                display_message
            fi
        else
            echo "($(timestamp)): ${PACKAGE_NAME} is not running on $IP_ADDRESS" | tee -a "$LOGFILE"
        fi
        
        adb disconnect "$IP_ADDRESS:${PORT}" >/dev/null 2>&1
        echo "($(timestamp)): Disconnected from $IP_ADDRESS" | tee -a "$LOGFILE"
    else
        echo "($(timestamp)): Failed to connect to $IP_ADDRESS:${PORT}" | tee -a "$LOGFILE"
    fi
}

# Function to display help message
show_help() {
    echo "Usage: $0 [-t duration] [-w wait] [-l logfile] [-p package_name] [-m message] [-x trackfile] [-h] IP [IP...]"
    echo
    echo "Options:"
    echo "  -t duration      Duration to check if the app needs to be turned off (in seconds, default: ${DURATION} seconds)"
    echo "  -w wait          Duration to wait before checking user interaction (in seconds, default: ${WAIT} seconds)"
    echo "  -l logfile       Log file path (default: /tmp/onn_<IP_ADDRESS>.log)"
    echo "  -n package_name  Package name of the app to check (default: ${PACKAGE_NAME})"
    echo "  -m message       Message to display (default: \"${MESSAGE}\")"
    echo "  -x trackfile     Track file path (default: ${TRACKFILE})"
    echo "  -p port          Port to connect on (default: ${PORT})"
    echo ""
    echo "  -h               Show this help message"
    echo ""
    echo "Ex. ${0} -t 10800 -w 30 192.168.1.1 192.168.1.2"
    exit 0
}

# Parse command-line arguments
while getopts "t:w:l:n:m:x:p:h" opt; do
    case ${opt} in
        t )
            DURATION=$OPTARG
            ;;
        w )
            WAIT=$OPTARG
            ;;
        l )
            LOGFILE=$OPTARG
            ;;
        n )
            PACKAGE_NAME=$OPTARG
            ;;
        m )
            MESSAGE=$OPTARG
            ;;
        x )
            TRACKFILE=$OPTARG
            ;;
        p )
            PORT=$OPTARG
            ;;
        h )
            show_help
            ;;
        \? )
           show_help
            ;;
    esac
done
shift $((OPTIND -1))

# Check if at least one IP address is provided
if [ "$#" -lt 1 ]; then
    echo "Error: At least one IP address is required."
    show_help
fi

# Process each IP address
for IP_ADDRESS in "$@"; do
    LOGFILE="/tmp/onn_${IP_ADDRESS}.log"
    process_device "$IP_ADDRESS"
done
