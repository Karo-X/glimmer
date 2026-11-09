#!/bin/bash
# Testet das leuchtende Apple-Logo auf dem MacBook Pro mit PROLED-XDR-Display.
#
#   ./logo-test.sh probe                  nur lesen: sucht Logo-Schnittstellen
#   ./logo-test.sh blink [anzahl] [sek]   schaltet das Logo an/aus, misst die Dauer
#   ./logo-test.sh lid [wartezeit-sek]    blinkt und spielt Ton bei geschlossenem Deckel
#
# DRY_RUN=1 zeigt die Befehle nur an und ändert nichts.
# blink und lid stellen beim Beenden (auch Ctrl-C) den alten Zustand wieder her.

set -u

DOMAIN=com.apple.CoreBrightness
KEY=LEBacklightMode
FRAMEWORK=/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness
SOUND=/System/Library/Sounds/Glass.aiff
DRY_RUN=${DRY_RUN:-0}
REPORT="${REPORT:-$PWD/logo-report-$(date +%Y%m%d-%H%M%S).txt}"

previous_mode=""
previous_sleep_disabled=""
restore_logo=0
restore_sleep=0

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'; }

run() {
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

log() { echo "$*" | tee -a "$REPORT"; }

logo_off() { run sudo defaults write "$DOMAIN" "$KEY" -int 0; }
logo_on() { run sudo defaults delete "$DOMAIN" "$KEY" 2>/dev/null; }

remember_logo() {
  previous_mode=$(sudo -n defaults read "$DOMAIN" "$KEY" 2>/dev/null || true)
  restore_logo=1
}

remember_sleep() {
  previous_sleep_disabled=$(pmset -g | awk '/SleepDisabled/ {print $2}')
  previous_sleep_disabled=${previous_sleep_disabled:-0}
  restore_sleep=1
}

cleanup() {
  trap - EXIT INT TERM
  if [ "$restore_logo" = 1 ]; then
    if [ -n "$previous_mode" ]; then
      run sudo defaults write "$DOMAIN" "$KEY" -int "$previous_mode"
    else
      logo_on
    fi
    log "Logo-Zustand wiederhergestellt."
  fi
  if [ "$restore_sleep" = 1 ]; then
    run sudo pmset -a disablesleep "$previous_sleep_disabled"
    log "Sleep-Einstellung wiederhergestellt (disablesleep=$previous_sleep_disabled)."
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

need_sudo() {
  [ "$DRY_RUN" = 1 ] && return
  sudo -v || exit 1
}

header() {
  log "Modell: $(sysctl -n hw.model), macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  log "Datum:  $(date)"
}

cmd_probe() {
  header
  log ""
  log "--- $KEY (aktuell) ---"
  log "$(defaults read "$DOMAIN" "$KEY" 2>&1 | head -1)"
  log ""
  log "--- CoreBrightness: exportierte Klassen ---"
  dyld_info -exports "$FRAMEWORK" 2>/dev/null | grep -oE '_OBJC_CLASS_\$_[A-Za-z0-9_]+' \
    | sed 's/_OBJC_CLASS_\$_//' | sort -u >>"$REPORT"
  log ""
  log "--- Geräte mit Logo-/Licht-Bezug ---"
  ioreg -l -w0 2>/dev/null | grep -oE '\+-o [A-Za-z0-9_@,.-]+' | sed 's/+-o //' \
    | grep -iE 'logo|lid|illum|pwm|led|backlight' | sort -u | tee -a "$REPORT"
  log ""
  log "--- Texte im System-Cache ---"
  local cache
  for cache in /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e*; do
    case "$cache" in *.map | *.atlas) continue ;; esac
    LC_ALL=C strings -n 6 "$cache" 2>/dev/null \
      | LC_ALL=C grep -E '^.{6,120}$' \
      | LC_ALL=C grep -E 'LEBacklight|[Ll]ogo(Brightness|Backlight|Luminance|Illum|PWM|Nits)|CBLogo|LidLogo' || true
  done | sort -u | tee -a "$REPORT"
  log ""
  log "Bericht: $REPORT"
}

cmd_blink() {
  local count=${1:-5} interval=${2:-1}
  header
  log "Blinktest: $count Zyklen, $interval s pro Phase. Schau aufs Logo."
  need_sudo
  remember_logo
  local i start end
  for ((i = 1; i <= count; i++)); do
    start=$(now_ms)
    logo_off
    end=$(now_ms)
    log "Zyklus $i: aus nach $((end - start)) ms"
    sleep "$interval"
    start=$(now_ms)
    logo_on
    end=$(now_ms)
    log "Zyklus $i: an nach $((end - start)) ms"
    sleep "$interval"
  done
  log "Bericht: $REPORT"
}

cmd_lid() {
  local wait_seconds=${1:-20} i
  header
  log "Deckeltest: Mac bleibt wach. Klappe ihn in den nächsten $wait_seconds s zu"
  log "und beobachte das Logo von außen. Nach der Wartezeit blinkt es 5-mal mit Ton."
  need_sudo
  remember_sleep
  remember_logo
  run sudo pmset -a disablesleep 1
  run sleep "$wait_seconds"
  log "Deckel geschlossen laut System: $(ioreg -r -k AppleClamshellState -d 1 | awk '/AppleClamshellState/ {print $3; exit}')"
  log "Logo jetzt 5 s normal an, danach 5 Blinkzyklen."
  run sleep 5
  for ((i = 1; i <= 5; i++)); do
    logo_off
    run sleep 1
    logo_on
    run afplay "$SOUND"
    run sleep 1
  done
  log "Fertig. Du kannst den Deckel wieder öffnen."
  log "Bericht: $REPORT"
}

case "${1:-}" in
  probe) cmd_probe ;;
  blink) shift; cmd_blink "$@" ;;
  lid) shift; cmd_lid "$@" ;;
  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
