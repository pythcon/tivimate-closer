# Tivimate Tracker and Controller

**The Problem**: I have a non-CEC TV. If I shut off the TV without closing Tivimate, it will continue to stream forever. I don't want that consuming bandwidth on my network. There is no way to get the state of the TV if it is a non-CEC TV. This script will solve this problem.

## Preview
![](https://github.com/pythcon/tivimate-closer/blob/master/preview.gif)

**TL;DR: This script will give you the classic "Are you still watching?" screen to save internet banwidth.**

The script will check if the app (Tivimate) is running, if so, it will start tracking it if no entry. If there is an entry, it will check if it has been running longer than it should be (DURATION). When this is the case, the script will tell Tivimate to open the search screen, and paste a message there. That message is customizable. If the user doesnt press the back button within the defined wait (WAIT) period, it will close the app and delete the line from the tracking file.

## Features

- Connects to Android devices using ADB.
- Checks if a specified app is running.
- Keeps track of the last time the app was checked.
- Closes the app if it has been running longer than a specified duration.
- Logs all actions and events.

## Prerequisites

The Android device must have debugging enabled. This script may fail on the first run and prompt you on the device to allow connections.

*I have tested this on the Onn 4K & Onn 4K Pro units and it works perfectly. Here are the instructions to enable ADB on the Onn units.*

#### Onn 4K / Onn 4K Pro
**Navigate to Settings > System > About > Android TV OS build. Click the Ok buttons 7 times to enable Developer Mode. Go back to the previous screen and enable USB ADB. This will also turn on the wireless ADB.**

## Usage

```bash
./tivimate-closer.sh [-t duration] [-w wait] [-l logfile] [-p package_name] [-m message] [-x trackfile] [-h] IP [IP...]

./tivimate-closer.sh -t 10800 -w 30 192.168.1.1 192.168.1.2
```

Scheduling this in cron is the ideal location for this script.
```bash
* * * * * /bin/bash -c "./adb_app_tracker.sh 192.168.1.1"
```
