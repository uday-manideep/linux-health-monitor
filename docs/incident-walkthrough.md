# Incident walkthrough: alert flood after VM boot

## Summary
After the VM was restarted, the first scheduled run reported 19 new log errors and raised an alert, although nothing was actually wrong.

## Timeline (2026-11-08)
- 12:30:01 cron launched the monitor.
- 12:30:02 the log showed `log_errors_new=19` and a `[WARN] Log errors: 19 new matches (threshold 5)` alert. The last matching line mentioned `obexd ... Error calling StartServiceByName`.

## Investigation
1. Read `logs/alerts.log` to see the alert and the last matching line.
2. Searched the syslog: `grep -iE "error|fail|segfault" /var/log/syslog | tail`.
3. The lines came from desktop and Bluetooth services (obexd, dbus-daemon, bluez) starting during boot in a VM that has no Bluetooth hardware.

## Root cause
The error filter matches keywords. Boot-time messages that contain the word "error" are harmless but were counted as real errors.

## Fix
- Added an `EXCLUDE_PATTERN` filter so known-harmless lines are not counted.
- Added an `ignored_noise` counter to each log line so filtered lines stay visible (for example `log_errors_new=0 (ignored_noise=6)`).
- A later alert for `dbus-org.bluez.service` led to adding `bluez` to the exclusion list.

## Verification
- 6 harmless lines produced `log_errors_new=0 (ignored_noise=6)` and no alert.
- 6 real error lines produced `log_errors_new=6` and an alert.

## Lessons
- Keyword-based detection needs a tunable exclusion list.
- Logging what was ignored keeps the filter honest and auditable.
- Reading only new log lines (byte offset) prevents repeated alerts, but boot-time bursts still need filtering.
