#!/bin/bash
# checks.sh — read-only Mac diagnostics for the /mac-check skill.
#
# Gathers facts across four domains (perf, disk, hygiene, security) and emits
# sectioned, parseable text. The skill (SKILL.md) interprets this output per
# CHECKS.md and decides what to do.
#
# INVARIANT: this script changes NOTHING. Safe cleanups (brew cleanup/autoremove)
# are the skill's responsibility, never this script's. Every section is guarded
# so one missing tool or failure cannot abort the run.

set -u

# Keep parsing deterministic on older macOS releases where C.UTF-8 is absent.
# Callers should also launch this script with LC_ALL=C to avoid a shell startup
# warning inherited from an invalid parent locale.
export LC_ALL=C

sec() { printf '\n========== %s ==========\n' "$1"; }
kv()  { printf '%-28s %s\n' "$1:" "$2"; }
sysctl_read() { sysctl -n "$1" 2>/dev/null || true; }
defaults_read() { defaults read "$1" "$2" 2>/dev/null || printf 'default'; }
probe() {
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -Eq 'Error:|Failed|Operation not permitted|Sandbox restriction'; then
    printf '%s\n' "$out"
  else
    printf 'unavailable: %s\n' "$(printf '%s\n' "$out" | head -1 | cut -c1-180)"
  fi
}

# du -sh with a bounded observer. macOS has no `timeout`, and file-provider
# trees (iCloud-synced containers) can wedge du inside an UNINTERRUPTIBLE
# syscall for minutes — kill does not reach it, so any wait/pipe bound to du
# blocks too. Here du runs fully detached with every inherited fd closed (it
# cannot hold the caller's pipes); the caller only polls a done-marker for
# <fuse> seconds. Prints the size field, "?" on du failure, "?<N>s" if fused.
du_fused() {  # du_fused <dir> <fuse_seconds>
  _dir="$1"; _fuse="$2"
  _t="/tmp/dufused.$$.$RANDOM"
  ( du -sh "$_dir" 2>/dev/null >"$_t.out"; : >"$_t.done" ) >/dev/null 2>&1 3>&- &
  _job=$!
  _n=0
  while [ "$_n" -lt "$_fuse" ] && [ ! -e "$_t.done" ]; do sleep 1; _n=$((_n+1)); done
  if [ -e "$_t.done" ]; then
    [ -s "$_t.out" ] && awk '{print $1}' "$_t.out" || echo "?"
  else
    kill "$_job" 2>/dev/null
    echo "?${_fuse}s"
  fi
  rm -f "$_t.out" "$_t.done" 2>/dev/null
}

# ---------------------------------------------------------------------------- META
sec "META"
kv "date"           "$(date '+%Y-%m-%d %H:%M')"
kv "macos"          "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
model="$(sysctl_read hw.model)"
cpu="$(sysctl_read machdep.cpu.brand_string)"
cores="$(sysctl_read hw.logicalcpu)"; [ -z "$cores" ] && cores="$(sysctl_read hw.ncpu)"
memsize="$(sysctl_read hw.memsize)"
kv "model"          "${model:-unavailable}"
kv "cpu"            "${cpu:-unavailable}"
kv "logical_cores"  "${cores:-unavailable}"
if [ -n "$memsize" ]; then
  kv "ram_gb"       "$(awk -v bytes="$memsize" 'BEGIN { printf "%.1f", bytes/1073741824 }')"
else
  kv "ram_gb"       "unavailable"
fi
uptime_out="$(uptime 2>/dev/null || true)"
case "$uptime_out" in
  *" up "*) kv "uptime" "up ${uptime_out#* up }" ;;
  *)        kv "uptime" "unavailable" ;;
esac

# ---------------------------------------------------------------------------- PERF
sec "PERF"
load_raw="$(sysctl_read vm.loadavg | tr -d '{}')"
kv "loadavg_1_5_15" "${load_raw:-unavailable}"
if [ -n "${cores:-}" ] && [ -n "$load_raw" ]; then
  read -r la1 la5 la15 <<< "$load_raw"
  load_pc="$(awk -v a="$la1" -v b="$la5" -v c="$la15" -v n="$cores" \
    'BEGIN { printf "%.2f %.2f %.2f", a/n, b/n, c/n }')"
  kv "load_per_core_1_5_15" "$load_pc  (>1.0 = saturated)"
else
  kv "load_per_core_1_5_15" "unavailable"
fi
swap="$(sysctl_read vm.swapusage)"
kv "swap"           "${swap:-unavailable}"

psize="$(sysctl_read hw.pagesize)"
vmstat="$(vm_stat 2>/dev/null || true)"
vmpages() { printf '%s\n' "$vmstat" | awk -v k="$1" '$0 ~ k {gsub(/\./, "", $NF); print $NF}' | head -1; }
if [ -n "$psize" ] && [ -n "$vmstat" ]; then
  pf="$(vmpages 'Pages free:')";     [ -z "$pf" ] && pf=0
  psp="$(vmpages 'Pages speculative:')"; [ -z "$psp" ] && psp=0
  pia="$(vmpages 'Pages inactive:')"; [ -z "$pia" ] && pia=0
  pcp="$(vmpages 'occupied by compressor')"; [ -z "$pcp" ] && pcp=0
  gib() { awk -v p="$1" -v s="$psize" 'BEGIN { printf "%.2f", p*s/1073741824 }'; }
  kv "available_gb"  "$(gib $((pf + psp + pia)))  (free+speculative+inactive)"
  kv "compressed_gb" "$(gib "$pcp")  (high = memory pressure)"
else
  kv "available_gb"  "unavailable"
  kv "compressed_gb" "unavailable"
fi
ps_out="$(ps aux 2>/dev/null || true)"
echo "--- top CPU ---"
if [ -n "$ps_out" ]; then
  printf '%s\n' "$ps_out" | sort -nrk3 | head -6 | awk '{printf "  %5.1f%% cpu  %4.1f%% mem  %s\n", $3, $4, $11}'
else
  echo "  unavailable (process inspection denied)"
fi
echo "--- top MEM ---"
if [ -n "$ps_out" ]; then
  printf '%s\n' "$ps_out" | sort -nrk4 | head -6 | awk '{printf "  %4.1f%% mem  %5.1f%% cpu  %s\n", $4, $3, $11}'
else
  echo "  unavailable (process inspection denied)"
fi

# ------------------------------------------------------------------------------ UI
sec "UI"
kv "reduce_motion"        "$(defaults_read com.apple.universalaccess reduceMotion)"
kv "reduce_transparency"  "$(defaults_read com.apple.universalaccess reduceTransparency)"
kv "window_animations"    "$(defaults_read NSGlobalDomain NSAutomaticWindowAnimationsEnabled)"
kv "finder_animations"    "$(defaults_read com.apple.finder DisableAllAnimations)  (1 = disabled)"
kv "dock_launch_animation" "$(defaults_read com.apple.dock launchanim)"
kv "dock_minimize_effect" "$(defaults_read com.apple.dock mineffect)"
kv "dock_show_recents"    "$(defaults_read com.apple.dock show-recents)"
kv "dock_autohide"        "$(defaults_read com.apple.dock autohide)"

# ---------------------------------------------------------------------------- DISK
sec "DISK"
df -h / | awk 'NR==1 || $1 ~ /\// {printf "  %-22s %6s %6s %6s %5s\n", $1, $2, $3, $4, $5}'
df / | awk 'NR==2 {printf "%-30s %.1f%%\n", "free_pct_root", $4/$2*100}'
echo "--- heaviest dirs (approx; ?>Ns = du fused after N seconds) ---"
for d in ~/Library/Caches ~/Library/"Application Support" ~/Library/Containers \
         ~/Library/"Group Containers" ~/Library/Developer ~/Library/Homebrew \
         ~/Downloads ~/Desktop ~/Documents ~/.Trash \
         "$(brew --cache 2>/dev/null)"; do
  [ -e "$d" ] && printf '  %-8s %s\n' "$(du_fused "$d" 30)" "$d"
done

# --------------------------------------------------------------------------- HYGIENE
sec "HYGIENE"
# Installed GUI apps + casks (inventory for spotting cruft beyond the known lists)
echo "--- /Applications ---"
ls /Applications 2>/dev/null | sed 's|^|  |'
if [ -d ~/Applications ] && [ -n "$(ls -A ~/Applications 2>/dev/null)" ]; then
  echo "--- ~/Applications ---"; ls ~/Applications 2>/dev/null | sed 's|^|  |'
fi
echo "--- browser versions ---"
for browser in "Brave Browser" "Google Chrome" "Safari" "Yandex"; do
  app="/Applications/$browser.app"
  [ -d "$app" ] || continue
  version="$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
  printf "  %-20s %s\n" "$browser" "${version:-unknown}"
done
echo "--- app footprint / last use (approximate metadata) ---"
for app in /Applications/*.app; do
  [ -d "$app" ] || continue
  app_size="$(du_fused "$app" 10)"
  app_owner="$(stat -f '%Su:%Sg' "$app" 2>/dev/null || true)"
  last_used="$(mdls -raw -name kMDItemLastUsedDate "$app" 2>/dev/null || true)"
  [ -z "$last_used" ] && last_used="unknown"
  printf "  %6s  %-12s %-32s %s\n" "${app_size:-?}" "${app_owner:-unknown}" "$(basename "$app")" "$last_used"
done
echo "--- brew counts ---"
printf "  formulae: %s   casks: %s\n" \
  "$(brew list --formula 2>/dev/null | awk 'END {print NR+0}')" \
  "$(brew list --cask 2>/dev/null | awk 'END {print NR+0}')"
echo "--- installed casks ---"
brew list --cask 2>/dev/null | sed 's|^|  |'
echo "--- largest Caskroom entries ---"
caskroom="$(brew --caskroom 2>/dev/null || true)"
if [ -n "$caskroom" ] && [ -d "$caskroom" ]; then
  for entry in "$caskroom"/*; do
    [ -e "$entry" ] && printf '%s\t%s\n' "$(du_fused "$entry" 15)" "$entry"
  done | sort -hr | head -15 | sed 's|^|  |'
else
  echo "  unavailable"
fi

# VPN clients — more than one is redundancy
echo "--- VPN clients found ---"
vpn_re='AmneziaVPN|Mullvad|Tunnelblick|Cloudflare WARP|WireGuard|Tailscale|OpenVPN|ExpressVPN|NordVPN|Surfshark|ProtonVPN|FortiClient|Cisco AnyConnect|Private Internet Access|VyprVPN|hide\.me'
vpn_count=0
for app in /Applications/*.app ~/Applications/*.app; do
  [ -e "$app" ] || continue
  b="$(basename "$app" .app)"
  if echo "$b" | grep -qiE "$vpn_re"; then
    printf "  %s (%s)\n" "$b" "$(dirname "$app")"
    vpn_count=$((vpn_count+1))
  fi
done
[ "$vpn_count" -eq 0 ] && echo "  (none matched)"
printf "  -> total VPN clients: %s\n" "$vpn_count"

# Known discontinued / EOL / risky apps
echo "--- known discontinued/EOL apps found ---"
disc_re='Boxcryptor|Flash Player|Adobe Flash|Silverlight|JavaAppletPlugin'
disc_count=0
for app in /Applications/*.app ~/Applications/*.app; do
  [ -e "$app" ] || continue
  b="$(basename "$app" .app)"
  if echo "$b" | grep -qiE "$disc_re"; then
    printf "  %s (/Applications)\n" "$b"; disc_count=$((disc_count+1))
  fi
done
[ -d /Library/Java/JavaVirtualMachines ] && ls /Library/Java/JavaVirtualMachines 2>/dev/null | sed 's|^|  JavaVM: |'
if [ -e "/Library/Internet Plug-Ins/JavaAppletPlugin.plugin" ]; then
  printf "  JavaAppletPlugin.plugin (legacy browser Java)\n"; disc_count=$((disc_count+1))
fi
[ "$disc_count" -eq 0 ] && echo "  (none matched)"

# Third-party launch daemons/agents — flag orphans (binary missing)
echo "--- 3rd-party launch daemons/agents (orphans flagged) ---"
for plist in /Library/LaunchDaemons/*.plist /Library/LaunchAgents/*.plist ~/Library/LaunchAgents/*.plist; do
  [ -f "$plist" ] || continue
  name="$(basename "$plist")"
  case "$name" in com.apple.*) continue;; esac
  label="$(plutil -extract Label raw "$plist" 2>/dev/null || true)"
  case "$plist" in
    /Library/LaunchDaemons/*) launch_domain="system" ;;
    *) launch_domain="gui/$(id -u)" ;;
  esac
  launch_info=""
  if [ -n "$label" ]; then
    launch_info="$(launchctl print "$launch_domain/$label" 2>/dev/null || true)"
  fi
  if [ -n "$launch_info" ]; then
    job_state="$(printf '%s\n' "$launch_info" | awk -F'= ' '/^[[:space:]]*state = / {print $2; exit}')"
    job_pid="$(printf '%s\n' "$launch_info" | awk -F'= ' '/^[[:space:]]*pid = / {print $2; exit}')"
    load_state="loaded/${job_state:-idle}"
    [ -n "$job_pid" ] && load_state="$load_state:$job_pid"
  else
    load_state="unloaded"
  fi
  prog="$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null)" || prog=""
  [ -z "$prog" ] && { prog="$(plutil -extract Program raw "$plist" 2>/dev/null)" || prog=""; }
  owner_missing=""
  case "$name" in
    com.docker.vmnetd.plist)
      [ -d /Applications/Docker.app ] || owner_missing="Docker.app missing"
      ;;
    com.citrix.ctxusbd.plist)
      if [ ! -d "/Applications/Citrix Workspace.app" ] && [ ! -d "/Applications/Citrix Receiver.app" ]; then
        owner_missing="Citrix app missing"
      fi
      ;;
  esac
  if [ -n "$prog" ] && [ "${prog:0:1}" = "/" ]; then
    if [ ! -e "$prog" ]; then
      printf "  ORPHAN   %-10s %s -> %s (binary missing)\n" "$load_state" "$name" "$prog"
    elif [ -n "$owner_missing" ]; then
      printf "  STALE?   %-10s %s -> %s (%s)\n" "$load_state" "$name" "$prog" "$owner_missing"
    else
      printf "  ok       %-10s %s -> %s\n" "$load_state" "$name" "$prog"
    fi
  else
    printf "  app-mgd  %-10s %s\n" "$load_state" "$name"
  fi
done

# Homebrew drift (all read-only / dry-run)
echo "--- brew drift ---"
echo "  [outdated formulae]"; brew outdated --formula 2>/dev/null | sed 's|^|    |'
echo "  [outdated casks]";    brew outdated --cask 2>/dev/null | sed 's|^|    |'
echo "  [missing]";    brew missing  2>/dev/null | sed 's|^|    |'
echo "  [autoremove -n would remove]"; brew autoremove -n 2>/dev/null | sed 's|^|    |'
echo "  [cleanup -n would free (approx)]"; brew cleanup -n 2>/dev/null | tail -3 | sed 's|^|    |'

# -------------------------------------------------------------------------- SECURITY
sec "SECURITY"
kv "gatekeeper" "$(probe spctl --status | head -1)"
kv "sip"        "$(probe csrutil status | head -1)"
kv "firewall"   "$(probe /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | head -1)"
kv "filevault"  "$(probe fdesetup status | head -1)"
kv "swupdate"   "$(probe softwareupdate --schedule | head -1)"
