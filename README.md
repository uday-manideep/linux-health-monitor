# Linux Health Monitor

A lightweight Bash tool that checks **CPU, memory, disk usage and system log errors** on a Linux machine every 5 minutes, writes **timestamped logs**, and raises **threshold-based alerts** for high usage and repeated errors.

Built and tested on Kali Linux (Debian-based) in VirtualBox; it uses only standard tools (`top`, `free`, `df`, `awk`, `grep`, `stat`, `tail`) and should run on Ubuntu too (Ubuntu test pending).

## Features

- CPU usage from two `top` samples (the first is an average since boot, so the second is used)
- Memory usage from `available` memory, not `free`
- Disk usage of the root filesystem
- Detects only NEW errors in `/var/log/syslog` using a saved byte offset (no repeated alerts for old errors)
- Handles log rotation and unreadable logs
- Exclusion filter for known-harmless log noise
- Configurable thresholds through environment variables
- Scheduled with cron, with `flock` so runs never overlap

## How it works

1. Read CPU, memory and disk values.
2. Write one `[INFO]` line with the readings to `logs/health.log`.
3. Compare each value with its threshold; if too high, write a `[WARN]` line and an `ALERT` line to `logs/alerts.log`.
4. Read only the new syslog lines since the last run, count those that match the error pattern (minus excluded noise), and alert if the count reaches the threshold.

## Usage

    chmod +x health_monitor.sh
    ./health_monitor.sh

Schedule every 5 minutes (see `crontab.example`):

    */5 * * * * flock -n /tmp/health_monitor.lock $HOME/linux-health-monitor/health_monitor.sh >> $HOME/linux-health-monitor/logs/cron.out 2>&1

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| CPU_THRESHOLD | 80 | CPU % that triggers an alert |
| MEM_THRESHOLD | 80 | Memory % that triggers an alert |
| DISK_THRESHOLD | 85 | Disk % that triggers an alert |
| ERROR_THRESHOLD | 5 | New matching log lines that trigger an alert |
| ERROR_PATTERN | error\|fail\|segfault | Words that count as errors |
| EXCLUDE_PATTERN | obexd\|StartServiceByName\|bluez\|IGNORE-ME | Known-harmless lines to ignore |
| SYSLOG | /var/log/syslog | Log file to scan |

Test an alert without real load: `CPU_THRESHOLD=0 ./health_monitor.sh`

## Sample output

See `examples/sample-health.log` and `examples/sample-alerts.log`. Example alert:

    2026-11-08 13:18:21 [WARN] Log errors: 6 new matches (threshold 5). Last: ... kali: REAL error 6

## Testing done

- Alerts forced with low thresholds
- Real CPU load with `yes` processes: 2 busy cores produced `cpu=52.5%` and a warning at a 40% threshold
- Fake errors written with `logger`: noise ignored, real errors counted
- First run, quiet run and log rotation behavior checked

## Incident walkthrough

See `docs/incident-walkthrough.md` for a real incident: an alert flood of harmless boot-time errors and how it was diagnosed and fixed.

## Known limitations

- Keyword matching can produce false positives, so the pattern and exclusion list are configurable.
- Under extreme CPU starvation the VM can delay the measurement itself.
- Alerts are written to a file; email or Slack delivery is a possible next step.
- Single machine only; for many servers use Prometheus and Grafana.

## Project structure

    health_monitor.sh        main script
    crontab.example          cron entry
    docs/incident-walkthrough.md
    examples/                sample log and alert output
    logs/ state/             created at runtime (not committed)
