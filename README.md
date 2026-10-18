# Linux System Monitor

A simple Bash-based system monitoring tool built as a Linux administration learning project.

## Features

- Displays hostname and timestamp.
- Shows system uptime.
- Monitors CPU usage.
- Monitors RAM usage.
- Checks root filesystem usage.
- Checks a selected systemd service.
- Records monitoring output to a local log file.
- Supports configurable warning thresholds.

## Requirements

- Linux operating system.
- Bash.
- `top`, `free`, `df`, `awk`, and `tee`.
- `systemd` for service checks.
- `cron` for scheduled monitoring.

## Installation

Clone the repository:

```bash
git clone https://github.com/mgaraar/linux-system-monitor.git
cd linux-system-monitor
```

## Usage

Run the monitoring script manually:

```bash
bash monitor.sh
```

The script displays system information and monitoring results in the terminal while recording output to a log file.

## Configuration

CPU, RAM, and disk warning thresholds can be configured in `monitor.sh`.

The log directory is configured through the `LOG_DIR` variable. For portability, the script can automatically detect its own directory so that the log file remains alongside `monitor.sh`, even when the project is cloned into a different directory.

Make sure the directory used for logging is writable by the user running the script.

## Automated Monitoring

The project can be scheduled with `cron` to run automatically at a configured interval.

Cron scheduling must be configured separately on each Linux device. Use the correct script path for the device where the project is installed.

## Limitations

- CPU parsing depends on the output format of `top`.
- Disk monitoring checks the root filesystem.
- Service checks require a compatible systemd environment.
- Cron requires an appropriate scheduling service and configuration.
- This is a learning project, not a production monitoring or alerting system.

## Future Improvements

- More robust CPU sampling.
- Better error handling.
- Unit tests.
- Scheduled monitoring.
- Structured log output.
- Improved log management.

