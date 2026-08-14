# CHECKS.md — how to interpret `checks.sh` output

Loaded by `SKILL.md` when interpreting a diagnostic run. Holds the **judgement**:
thresholds, severity, the macOS support table, and the auto-vs-manual line.
The script gathers facts; this file tells you what they mean for *this* machine
(daily-driver MacBook with important data, 8 GB RAM, EOL macOS — see profile below).

## Machine profile (this Mac)

- **Model:** MacBookPro12,1 = MacBook Pro (Retina 13", Early 2015). ~11 years old.
- **RAM:** 8 GB — hardware ceiling. Memory pressure is a **known limit**, not a bug to "fix" by tuning. Flag as *Accepted*, suggest quitting hogs / fewer browsers, never promise a software cure.
- **macOS:** max officially supported = **12 Monterey**. Cannot upgrade via Apple. The only upgrade path is OCLP (OpenCore Legacy Patcher) — advanced, out of scope; mention as the sole option, do not push.

## macOS support window (verify against Apple's security releases)

Do not infer support from version arithmetic alone. Check Apple's current security
releases when this table may be stale. As of August 2026, Apple is publishing
security releases for macOS Tahoe 26, Sequoia 15, and Sonoma 14; Monterey's
last security release was 12.7.6 on 2024-07-29.

| macOS | Status |
|---|---|
| 26 Tahoe, 15 Sequoia, 14 Sonoma | Receiving security patches |
| 13 Ventura | EOL |
| **12 Monterey and below** | **EOL — no security patches** ← this machine |

`macos:` showing 12.x → **CRITICAL security risk**. Since it cannot be upgraded
through Apple, mitigations are the response (see below), not "update the OS".
If STATE.md already records this as Accepted/Decided, report it as a known
accepted risk rather than adding a duplicate Pending item.

## Severity assignment

- **CRITICAL** — security exposure on a data-bearing machine: EOL OS *without* mitigations in place; **FileVault Off**; Gatekeeper / SIP / firewall disabled; credentials/exfil risk.
- **WARNING** — redundancy or meaningful degradation: ≥2 VPN clients; free disk <20%; sustained memory pressure (swap growing, available <1 GB); large number of outdated packages; orphan launch daemons; discontinued app still installed.
- **INFO** — housekeeping: outdated formulae (routine), oversized caches (cleanup opportunity), long uptime (reboot suggested), minor cruft.

## Metric thresholds

| Metric (from output) | INFO | WARNING | CRITICAL |
|---|---|---|---|
| `load_per_core_1_5_15` | ≤1.0 | 1.0–2.0 sustained | >2.0 sustained |
| `available_gb` | >2 | 1–2 | <1 |
| `compressed_gb` | <1 | 1–2 | >2 (8 GB box) |
| `swap` used | <256 MB | 256 MB–1 GB | >1 GB & growing |
| `free_pct_root` | >20% | 10–20% | <10% |

**Judge load against the 5/15-min per-core values and `uptime`, not the 1-min
spike** — the check itself (and an agent running it) inflates instantaneous
load. A single sample above 1 is not actionable. Also read the trend: a high
15-minute value with much lower 1/5-minute values is a recovering load, not a
currently worsening one.

## Domain-specific rules

### Perf
- The fixable levers here are **few**: quit top CPU/MEM hogs you don't need, reduce browser tab/process count, reboot if uptime is long *and* load is high. Do **not** recommend "RAM cleaner" apps or purging — snake oil on macOS.
- Heavy hitters seen on this box: `claude`, multiple `Brave` processes, `Bitwarden`, `WindowServer`, `kitty`. Flag only if surprising.

### UI responsiveness
- On this Intel/Iris 2015 Mac, Reduce Motion and Reduce Transparency are safe,
  reversible ways to reduce WindowServer compositing work. Treat them as INFO,
  not as a cure for CPU or RAM pressure.
- The low-risk Dock profile is: Scale minimize effect, launch animation off,
  recent apps off. Do not recommend undocumented ultra-short animation timings;
  they tend to make the UI feel broken and offer no sustained performance gain.
- Installed apps consume disk but not RAM merely by existing. Use the app
  footprint/last-use inventory to suggest candidates; never delete based on
  age metadata alone because Spotlight metadata can be incomplete.

### Disk
- `brew cleanup -n` reports space it *would* free → the skill runs `brew cleanup` for real (AUTO). Same for `brew autoremove` (removes orphaned dependencies — safe).
- Biggest historical lever here is `~/Library/Application Support` (previously
  ~15 GB; ~7 GB after cleanup) — do **not** auto-delete; have the user inspect
  per-app subfolders only when disk is actually constrained. Print
  `du -sh ~/Library/Application\ Support/* | sort -rh | head` as a follow-up.
- Trash (`~/.Trash`), `~/Downloads`, `~/Desktop` are user data — suggest reviewing, never delete.

### Hygiene
- **VPN redundancy:** ≥2 VPN clients = WARNING labelled "review for consolidation", **not** "delete all but one". Reason: Tailscale/WireGuard are mesh/transport (LAN access, exit nodes) and serve a different role than a privacy VPN (Mullvad). Ask the user which role each fills before recommending removal. An *orphaned* VPN daemon (e.g. `net.mullvad.daemon` with no matching app) is unambiguous cruft → safe to remove.
- **Discontinued apps:** Boxcryptor (EOL 2023, discontinued after Dropbox acquisition) → remove if unused (its daemon is an orphan too). Flash Player / `JavaAppletPlugin.plugin` → security risk, remove. Oracle Java → if nothing needs it, remove; if needed, prefer Temurin (`brew install --cask temurin`) over Oracle.
- **Orphan launch daemons** (`ORPHAN ... binary missing`): the app was uninstalled but its plist remains. Safe to remove — needs `sudo` for `/Library/LaunchDaemons` (MANUAL). Command template: `sudo launchctl bootout system <plist> ; sudo rm <plist>` (and the matching `~/Library/LaunchAgents` variant without sudo). `app-mgd` / `ok` lines are not actionable.
- **Stale helpers** (`STALE? ... owner app missing`): the privileged helper still
  exists but its expected GUI app is absent. Ask whether the user still needs
  the product before removal. If not, remove its plist and exact helper binary
  as a MANUAL action; warn that reinstalling the app will be required to restore
  the helper.
- **brew outdated:** routine → INFO. On this Monterey machine, do **not** suggest
  blanket `brew upgrade`: many current formulae lack Monterey bottles and would
  trigger long source builds. The wrapper in `~/.zshrc` enforces
  `--force-bottle`. If an upgrade is useful, verify bottle availability and
  propose a targeted command. `brew missing` empty = good.

### Security (the priority domain for this machine)
- **FileVault Off → CRITICAL.** Stolen laptop = full disk readable. Action is MANUAL and must warn: `fdesetup enable` encrypts in the background for hours; keep the machine plugged in and awake until done; **save the recovery key**. On an 11-yo SSD that's near-full, confirm free space first.
- Gatekeeper `assessments enabled`, SIP `enabled`, firewall `enabled` = good (no action). Any of these off → WARNING/CRITICAL.
- `softwareupdate --schedule` on = good.
- **EOL OS mitigations** (the response to "cannot upgrade"): verify that the
  browser vendor still supports Monterey before calling it current, remove
  unused/old software (shrinks attack surface), keep firewall + Gatekeeper on,
  and note the machine should be on a replacement timeline. FileVault remains
  strongly recommended, but respect a recorded user decision not to enable it.

## Auto vs manual (the autonomy line)

**AUTO — the skill runs these directly, then reports what it freed/removed:**
- `brew cleanup` (frees cache / old versions)
- `brew autoremove` (removes orphaned dependencies)

**MANUAL — the skill prints the exact command with a one-line risk note, adds to STATE.md `Pending`, does NOT run:**
- App uninstall (`rm -rf /Applications/X.app`; recommend AppCleaner for full removal)
- Launch daemon removal (`sudo launchctl bootout … ; sudo rm …`)
- `brew upgrade` (version churn)
- Deleting caches beyond Homebrew's
- `fdesetup enable` (FileVault)

If anything is ambiguous or could touch user data, default to MANUAL.
