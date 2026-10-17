
# Linux System Monitor

A simple Bash-based system monitoring tool
built as a Linux administration learning project.

## Features

- Displays hostname and timestamp
- Monitors CPU usage
- Monitors RAM usage
- Checks root filesystem usage
- Checks a selected systemd service
- Records output to a local log file
- Supports configurable warning thresholds

## Requirements

- Linux
- Bash
- `top`, `free`, `df`, `awk`, `tee`
- systemd for service checks

## Usage

```bash
bash monitor.sh
```

## Configuration

The CPU, RAM, and disk warning thresholds
can be configured in `monitor.sh`.

## Limitations

- CPU parsing depends on the output format of `top`.
- Disk monitoring checks the root filesystem.
- Service checks require systemd.
- This is a learning project, not a production
  monitoring or alerting system.

## Future Improvements

- More robust CPU sampling
- Better error handling
- Unit tests
- Scheduled monitoring
- Structured log output

