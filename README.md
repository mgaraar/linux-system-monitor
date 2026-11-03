# Linux System Monitor

[![CI](https://github.com/mgaraar/linux-system-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/mgaraar/linux-system-monitor/actions/workflows/ci.yml)

A simple Bash-based system monitoring tool built as a Linux administration learning project.

## Features

- Displays hostname, timestamp, and tool version.
- Reports CPU, RAM, swap, and root filesystem usage with configurable warning thresholds.
- Samples CPU usage from `/proc/stat` (no dependency on `top` output format).
- Reports load average normalized against the number of CPU cores.
- Shows the top processes by CPU usage.
- Checks a selected systemd service, falling back from `ssh.service` to `sshd.service`.
- Records every run to a log file stored next to the script, with size-based trimming.
- Prevents overlapping runs with an internal `flock`.
- Reads configuration from a config file, environment variables, or CLI flags.
- Sends an optional webhook notification when a warning or error occurs.
- Returns meaningful exit codes for use in cron or other automation.
- Supports JSON output for integration with other tools.

## Requirements

- Linux operating system.
- Bash 4 or newer.
- `free`, `df`, `awk`, `ps`, and `tee`.
- `/proc/stat` and `/proc/loadavg` (standard on Linux).
- `flock` from `util-linux` for run locking (optional).
- `systemd` and `systemctl` for service checks.
- `curl` for webhook notifications (optional).
- `cron` or a systemd timer for scheduled monitoring.

## Installation

Clone the repository:

```bash
git clone https://github.com/mgaraar/linux-system-monitor.git
cd linux-system-monitor
```

Optionally create a local configuration file:

```bash
cp config.example.sh config.sh
```

`config.sh` is ignored by git, so local settings stay out of the repository.

## Usage

Run the monitoring script manually:

```bash
bash monitor.sh
```

Show all available options:

```bash
bash monitor.sh --help
```

### Options

| Option | Description | Default |
| --- | --- | --- |
| `-s`, `--service <name>` | systemd service to check | `ssh.service` |
| `-t`, `--threshold <1-100>` | Warning threshold in percent for CPU, RAM, disk, and swap | `80` |
| `--config <file>` | Load configuration from a specific file | `config.sh` next to the script |
| `--json` | Print the result as a single JSON object | off |
| `-h`, `--help` | Show usage information | - |

### Examples

```bash
# Check nginx instead of ssh, warn at 90%
bash monitor.sh -s nginx.service -t 90

# Machine-readable output for dashboards or scripts
bash monitor.sh --json

# Use a specific config file
bash monitor.sh --config /etc/linux-system-monitor.conf

# Use the exit code in cron or a wrapper script
bash monitor.sh --json >/dev/null || notify-someone
```

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Everything is normal, or the run was skipped because another instance holds the lock. |
| `1` | A metric reached its threshold, or the checked service is not active. |
| `2` | Data could not be read, the service was not found, `systemd` is unavailable, or arguments/configuration were invalid. |

## Output

Text mode prints a human-readable report with system information, metric status, memory and disk details, the top processes by CPU, service state, and an overall status line.

JSON mode prints one object per run (pretty-printed here for readability; the script emits it as a single line):

```json
{
  "timestamp": "2026-11-03 14:15:19",
  "hostname": "example-host",
  "version": "2.0.0",
  "threshold": 80,
  "metrics": {
    "cpu": { "value": 1, "status": "normal" },
    "ram": { "value": 14, "status": "normal" },
    "disk": { "value": 1, "status": "normal" },
    "swap": { "value": 0, "status": "normal" },
    "load": { "value": 0.08, "cores": 12, "status": "normal" }
  },
  "service": { "name": "ssh.service", "state": "active", "detail": "active" },
  "status": "ok",
  "exit_code": 0
}
```

- Metric `status` is `normal`, `warning`, or `error`, and `value` is `null` when the metric could not be read.
- `swap` uses `skipped` when the machine has no swap configured.
- `load` warns when the 1-minute average reaches the number of CPU cores.
- Service `state` is `active`, `inactive`, `not-found`, or `unavailable`.

## Configuration

Settings are resolved in this order, later entries winning:

1. Built-in defaults.
2. `config.sh` next to the script (or the file given with `--config`).
3. Environment variables with the `MONITOR_` prefix.
4. CLI flags `-s` and `-t`.

| Variable | Meaning | Default |
| --- | --- | --- |
| `MONITOR_SERVICE` | systemd service to check | `ssh.service` |
| `MONITOR_THRESHOLD` | Warning threshold in percent | `80` |
| `MONITOR_LOG_DIR` | Log directory, relative to the script or absolute | script directory |
| `MONITOR_LOG_MAX_LINES` | Trim the log once it exceeds this many lines (`0` disables) | `5000` |
| `MONITOR_SAMPLE_INTERVAL` | Delay between the two CPU samples, in seconds | `0.5` |
| `MONITOR_TOP_PROCESSES` | Number of top processes to show (`0` disables) | `3` |
| `MONITOR_LOCK_FILE` | Lock file used to prevent overlapping runs (empty disables) | `/tmp/linux-system-monitor.lock` |
| `MONITOR_NOTIFY_WEBHOOK` | Webhook URL for notifications (empty disables) | empty |
| `MONITOR_NOTIFY_ON` | When to notify: `warning`, `error`, `always`, `never` | `warning` |
| `MONITOR_CONFIG` | Alternative configuration file path | `config.sh` |

Example using the environment:

```bash
MONITOR_THRESHOLD=90 MONITOR_SERVICE=nginx.service bash monitor.sh
```

### Log handling

Each run appends to `monitor.log` in the configured log directory. When the file exceeds `MONITOR_LOG_MAX_LINES`, the oldest half is discarded before the new run is written, so the log stays bounded without needing external rotation. Set `MONITOR_LOG_MAX_LINES=0` if you prefer to handle rotation with `logrotate` instead.

If the log directory is not writable, the script prints a warning and still runs without logging.

## Notifications

Set `MONITOR_NOTIFY_WEBHOOK` to a URL and the script sends an HTTP `POST` with a JSON body when the configured condition is met:

```json
{
  "text": "[WARNING] example-host - CPU 91%, RAM 42%, DISK 12%",
  "content": "[WARNING] example-host - CPU 91%, RAM 42%, DISK 12%",
  "hostname": "example-host",
  "status": "warning"
}
```

Both `text` and `content` keys are included so the same payload works with Slack-style and Discord-style webhooks. The request has a 5-second timeout and failures are ignored, so a broken webhook never changes the monitoring result. Notifications are sent before exiting, and only when `curl` is available.

## Automated Monitoring

### cron

```cron
# Every 5 minutes; flock guards against a slow run overlapping the next one
*/5 * * * * /usr/bin/flock -n /tmp/system-monitor.lock /path/to/monitor.sh >/dev/null 2>&1
```

Because the script returns exit code `1` on warnings, cron can also trigger an alert:

```cron
*/5 * * * * /path/to/monitor.sh >/dev/null 2>&1 || echo "system monitor warning" | mail -s "Warning" admin@example.com
```

### systemd timer

Unit examples live in `systemd/`:

```bash
sudo cp systemd/linux-system-monitor.service /etc/systemd/system/
sudo cp systemd/linux-system-monitor.timer /etc/systemd/system/
# Edit ExecStart/WorkingDirectory in the service to match your install path
sudo systemctl daemon-reload
sudo systemctl enable --now linux-system-monitor.timer
```

The timer runs once a minute after boot and every five minutes thereafter. Check the last result with:

```bash
systemctl status linux-system-monitor.service
journalctl -u linux-system-monitor.service -n 50
```

## Limitations

- CPU usage is a short sample (default 0.5 seconds), not a long-term average.
- Load average is compared against the total number of cores, without per-core normalization or history.
- Disk monitoring checks the root filesystem only.
- Service checks require `systemctl` with `systemd` running as PID 1.
- The process list relies on GNU `ps` (`--sort`); minimal `ps` implementations may not support it.
- Log trimming is line-based, not byte- or date-based, and can cut a report in half.
- JSON output is intentionally minimal and not a stable public schema yet.
- This is a learning project, not a production monitoring or alerting system.

## Future Improvements

- External alerting integrations beyond a generic webhook (email, PagerDuty, Telegram).
- Metrics history and simple trend output.
- Packaging as a `.deb` or container image.
- Structured log output.

## Development

Development tooling is optional; the monitor itself only needs the runtime requirements above.

```bash
# Debian/Ubuntu
sudo apt-get install -y bats shellcheck

# shfmt (Go toolchain)
go install mvdan.cc/sh/v3/cmd/shfmt@latest

# or download the static binary from https://github.com/mvdan/sh/releases
```

### Commands

```bash
make test        # bats test suite
make lint        # shellcheck
make fmt         # format in place
make fmt-check   # verify formatting without writing
make check       # lint + fmt-check + test (what CI runs)
```

### Test layout

```text
tests/
├── helpers/common.bash   # fake free/df/ps/systemctl builders
├── unit/                 # classify, CPU math, service state
└── integration/          # CLI, full run, lock, log rotation, config precedence
```

`monitor.sh` can be sourced safely: the CLI only runs when the file is executed
directly (`BASH_SOURCE` guard). Tests use that to call pure helpers such as
`cpu_percent_from_samples` and `check_service` without starting a full run.
Integration tests inject fake binaries through `PATH`, so no test touches the
real system state.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 mgaraar.
