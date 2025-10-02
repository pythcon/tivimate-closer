# TiviMate Closer

Automatically close TiviMate on Android TV devices after a period of inactivity to save bandwidth.

**The Problem**: Non-CEC TVs can't tell apps when they're turned off. TiviMate keeps streaming forever, wasting bandwidth. This tool gives you the classic "Are you still watching?" prompt.

## Preview
![](https://github.com/pythcon/tivimate-closer/blob/master/preview.gif)

## Quick Start

### Option 1: Docker (Recommended)

```bash
# Clone and configure
git clone <your-repo-url>
cd tivimate-closer

# Edit docker-compose.yml - Set your device IP
nano docker-compose.yml

# Run
docker-compose up -d
```

### Option 2: Standalone Script

```bash
# Single check
./tivimate-closer.sh 192.168.1.100

# Run as service (continuous monitoring)
./tivimate-closer.sh -s -i 60 192.168.1.100
```

## Setup Your Android TV

Enable ADB debugging on your device:

1. Go to **Settings** → **About**
2. Click on **Build** 7 times to enable Developer Mode
3. Go to **Settings** → **Developer Options**
4. Enable **Network Debugging** or **ADB Debugging**

**Onn 4K / Onn 4K Pro**: Settings → System → About → Android TV OS build (click 7 times) → Enable USB ADB

## Configuration

Edit `docker-compose.yml`:

```yaml
environment:
  # Your device IP(s)
  DEVICE_IPS: "192.168.1.100"              # Single device
  # DEVICE_IPS: "192.168.1.100,192.168.1.101"  # Multiple devices

  # Timing (in seconds)
  DURATION: "10800"         # 3 hours until warning
  CHECK_INTERVAL: "60"      # Check every minute
  WAIT_TIME: "30"          # Wait 30s for user response

  # Android 12+ compatibility
  ACTIVITY_RESUME_PATTERN: "ResumedActivity"  # Use "mResumedActivity" for Android 11-
```

## How It Works

1. **Monitors** - Checks if TiviMate is running every `CHECK_INTERVAL` seconds
2. **Tracks** - Records when app started running
3. **Warns** - After `DURATION`, displays on-screen message
4. **Waits** - Gives user `WAIT_TIME` seconds to respond
5. **Closes** - If no response, closes TiviMate

## Script Options

```bash
./tivimate-closer.sh [OPTIONS] IP [IP...]

OPTIONS:
  -s          Service mode (continuous monitoring)
  -i seconds  Check interval (default: 60)
  -t seconds  Duration before warning (default: 10800)
  -w seconds  Wait time for response (default: 30)
  -r pattern  Android activity pattern (mResumedActivity or ResumedActivity)
  -m message  Warning message (auto-converts to ADB format)
  -p package  Package name (default: ar.tvplayer.tv)
```

## Examples

### Docker Service
```bash
docker-compose up -d        # Start service
docker-compose logs -f      # View logs
docker-compose down         # Stop service
```

### Standalone Script
```bash
# One-time check
./tivimate-closer.sh 192.168.1.100

# Service mode
./tivimate-closer.sh -s -i 60 192.168.1.100

# Custom timing
./tivimate-closer.sh -t 7200 -w 45 192.168.1.100

# Android 12+ device
./tivimate-closer.sh -r ResumedActivity 192.168.1.100
```

### Cron Job
```bash
# Check every 5 minutes
*/5 * * * * /path/to/tivimate-closer.sh 192.168.1.100
```

## Troubleshooting

### Device Won't Connect

1. **First time**: Check TV screen for "Allow USB debugging" prompt
2. **Auth failed**: Device needs authorization - check TV screen
3. **Test connection**:
```bash
docker-compose exec tivimate-closer adb devices
# or
adb connect 192.168.1.100:5555
```

### Android Version Issues

Different Android versions use different activity patterns:
- **Android 11-**: `mResumedActivity` (default)
- **Android 12+**: `ResumedActivity`

Test which works:
```bash
adb shell dumpsys activity activities | grep mResumedActivity
# or
adb shell dumpsys activity activities | grep ResumedActivity
```

### Reset ADB Keys

```bash
# Docker
docker-compose down -v

# Standalone
rm -rf ~/.android
```

## Features

- 🐳 **Docker Support** - Easy deployment with persistent ADB keys
- 📊 **Multi-device** - Monitor multiple Android TVs
- ⏰ **Configurable Timers** - Custom inactivity periods
- 🔄 **Service Mode** - Run continuously or one-time
- 📝 **Human-Readable Messages** - Auto-converts to ADB format
- 🤖 **Android 12+ Support** - Compatible with latest Android TV

## Requirements

- Docker & Docker Compose (for Docker mode)
- ADB tools (for standalone mode)
- Android TV with network debugging enabled
- Same network as your Android TV devices

## License

See LICENSE file for details.