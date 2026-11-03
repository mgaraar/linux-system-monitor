# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2026-11-03

### Added

- `--watch [detik]` mode: refresh layar terus-menerus memakai alternate screen,
  dengan `Ctrl+C` yang mengembalikan terminal ke kondisi semula.
- `--no-log` dan `--no-lock` untuk melewati penulisan log dan file lock.
- Cache sampel `/proc/stat` di `${TMPDIR:-/tmp}/linux-system-monitor.cpu` agar
  mode watch menghitung CPU tanpa menunggu sampling setiap frame.
- Konfigurasi `MONITOR_WATCH_INTERVAL` dan `MONITOR_CACHE_FILE`.

### Changed

- Mode watch otomatis tidak menulis log, tidak memakai lock, dan tidak
  mengirim notifikasi webhook.
- `--watch` tidak dapat digabung dengan `--json`.

## [2.0.0] - 2026-11-03

### Added

- Swap, load average, and top-process metrics.
- Configuration through `config.sh`, `MONITOR_*` environment variables, and the
  `--config` flag, with documented precedence.
- Line-based log trimming through `MONITOR_LOG_MAX_LINES`.
- Internal `flock` so scheduled runs never overlap.
- Optional webhook notifications with `MONITOR_NOTIFY_WEBHOOK` and
  `MONITOR_NOTIFY_ON`.
- systemd service and timer units under `systemd/`.
- `config.example.sh`, `Makefile`, CI workflow, and bats test suite.
- MIT license and this changelog.

### Changed

- Configuration is resolved as CLI > environment > config file > defaults.
- JSON output now includes `swap` and `load` metrics.
- Log directory is created on demand and reported when not writable.

## [1.1.0] - 2026-11-03

### Added

- CLI options `-s/--service`, `-t/--threshold`, `--json`, and `-h/--help`.
- Meaningful exit codes: `0` normal, `1` warning, `2` error.
- JSON output mode.
- `sshd.service` fallback and tolerant systemd version handling.

### Changed

- CPU usage is sampled from `/proc/stat` instead of parsing `top`.
- `LC_ALL=C` is exported for consistent parsing.

### Fixed

- Locale-dependent number parsing.
- RAM handling when `free` has no `available` column.
- Removed an inappropriate line from the report output.

## [1.0.0] - 2026-10-17

### Added

- Initial Bash system monitor reporting CPU, RAM, disk, and one systemd service.
- Warning thresholds and logging to `monitor.log`.
