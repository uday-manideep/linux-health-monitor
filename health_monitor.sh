#!/bin/bash
# health_monitor.sh - version 5: adds an exclusion filter for harmless log noise

BASE_DIR="$HOME/linux-health-monitor"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/state"
LOG_FILE="$LOG_DIR/health.log"
ALERT_FILE="$LOG_DIR/alerts.log"
OFFSET_FILE="$STATE_DIR/syslog.offset"
SYSLOG="${SYSLOG:-/var/log/syslog}"
mkdir -p "$LOG_DIR" "$STATE_DIR"

# Thresholds (percent) and error settings. Override from outside for testing.
CPU_THRESHOLD=${CPU_THRESHOLD:-80}
MEM_THRESHOLD=${MEM_THRESHOLD:-80}
DISK_THRESHOLD=${DISK_THRESHOLD:-85}
ERROR_THRESHOLD=${ERROR_THRESHOLD:-5}
ERROR_PATTERN=${ERROR_PATTERN:-"error|fail|segfault"}
# Lines matching this are known harmless noise and are not counted
EXCLUDE_PATTERN=${EXCLUDE_PATTERN:-"obexd|StartServiceByName|bluez|IGNORE-ME"}

# log LEVEL MESSAGE -> prints and appends "date time [LEVEL] message"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" | tee -a "$LOG_FILE"
}

# raise_alert MESSAGE -> WARN in health.log plus a line in alerts.log
raise_alert() {
    log WARN "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ALERT $1" >> "$ALERT_FILE"
}

# is_high VALUE LIMIT -> succeeds if VALUE >= LIMIT (works with decimals)
is_high() {
    awk -v v="$1" -v l="$2" 'BEGIN{exit !(v+0 >= l+0)}'
}

# check_log_errors: count NEW matching lines since the last run
check_log_errors() {
    if [ ! -r "$SYSLOG" ]; then
        log WARN "cannot read $SYSLOG (check permissions)"
        return
    fi
    local size offset matches count excluded sample
    size=$(stat -c %s "$SYSLOG")
    if [ -f "$OFFSET_FILE" ]; then
        offset=$(cat "$OFFSET_FILE")
    else
        offset=$size    # first run: start from now, ignore old history
    fi
    if [ "$offset" -gt "$size" ]; then
        offset=0        # log was rotated (file is smaller), start over
    fi
    # all new lines that look like errors
    matches=$(tail -c +$((offset+1)) "$SYSLOG" | grep -iE "$ERROR_PATTERN")
    # same lines minus the known-harmless ones
    real=$(echo "$matches" | grep -viE "$EXCLUDE_PATTERN" | grep -v '^$')
    count=$(echo -n "$real" | grep -c '^')
    excluded=$(( $(echo -n "$matches" | grep -c '^') - count ))
    sample=$(echo "$real" | tail -n1 | cut -c1-150)
    echo "$size" > "$OFFSET_FILE"
    log INFO "log_errors_new=${count} (ignored_noise=${excluded})"
    if [ "$count" -ge "$ERROR_THRESHOLD" ]; then
        raise_alert "Log errors: ${count} new matches (threshold ${ERROR_THRESHOLD}). Last: ${sample}"
    fi
}

# CPU: two samples 1 second apart; use the second line; usage = 100 - idle
CPU_IDLE=$(top -bn2 -d1 | grep "Cpu(s)" | tail -n1 | awk '{for(i=1;i<=NF;i++) if($i=="id,") print $(i-1)}')
CPU_USED=$(awk -v idle="$CPU_IDLE" 'BEGIN{printf "%.1f", 100-idle}')

# Memory: (total - available) / total * 100
MEM_USED=$(free | awk '/^Mem:/ {printf "%.1f", ($2-$7)/$2*100}')

# Disk: Use% of the root filesystem, without the % sign
DISK_USED=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')

log INFO "cpu=${CPU_USED}% mem=${MEM_USED}% disk=${DISK_USED}%"

is_high "$CPU_USED"  "$CPU_THRESHOLD"  && raise_alert "CPU usage ${CPU_USED}% is at or above threshold ${CPU_THRESHOLD}%"
is_high "$MEM_USED"  "$MEM_THRESHOLD"  && raise_alert "Memory usage ${MEM_USED}% is at or above threshold ${MEM_THRESHOLD}%"
is_high "$DISK_USED" "$DISK_THRESHOLD" && raise_alert "Disk usage ${DISK_USED}% is at or above threshold ${DISK_THRESHOLD}%"

check_log_errors

exit 0
