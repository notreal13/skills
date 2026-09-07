# CHECKS.md — how to interpret `checks.sh` output

Loaded by `SKILL.md` when interpreting a diagnostic run. Holds the **judgement**:
thresholds, severity, the macOS support table, and the auto-vs-manual line.
The script gathers facts; this file tells you what they mean for *this* machine.
One repo serves **two Macs** — match the `model:` line from the META section to
a profile below before applying any rule, and use only that machine's
`state/<model>.md` for continuity.

## Machine profiles (match `model:` from META)

### MacBookPro12,1 — старый мак (state/MacBookPro12_1.md)

- **Model:** MacBook Pro (Retina 13", Early 2015). ~11 years old.
- **RAM:** 8 GB — hardware ceiling. Memory pressure is a **known limit**, not a bug to "fix" by tuning. Flag as *Accepted*, suggest quitting hogs / fewer browsers, never promise a software cure.
- **macOS:** max officially supported = **12 Monterey**. Cannot be upgraded via Apple. The only upgrade path is OCLP (OpenCore Legacy Patcher) — advanced, out of scope; mention as the sole option, do not push.
- **Homebrew:** most current formulae have **no monterey bottles** → blanket `brew upgrade` triggers forbidden source builds. The `brew()` wrapper in `~/.zshrc` enforces `--force-bottle` (escape hatch `HOMEBREW_ALLOW_SOURCE=1`). Node is managed by **nvm** (prebuilt binaries), not brew.
- **FileVault:** recorded user decision — intentionally off, wontfix (EOL-OS exposure acknowledged).
- **Historical disk lever:** `~/Library/Application Support` (peaked ~15 GB, ~7 GB after cleanups).

### Mac16,13 — новый мак, MacBook Air 13" M4 (state/Mac16_13.md)

- **Model:** MacBook Air 13" (M4, 2025). arm64, Homebrew в `/opt/homebrew`.
- **RAM:** 24 GB — memory pressure findings need the 24 GB thresholds below before they count.
- **macOS:** 26.x — inside Apple's current security window; treat "update the OS" as a normal actionable finding, not a dead end.
- **Homebrew:** arm64-бутылки существуют для всего актуального → blanket `brew upgrade` допустим (по-прежнему MANUAL по линии автономности).
- **FileVault:** решение старого мака (wontfix) **не переносится** — на первом чеке спросить пользователя и записать новое решение в state/Mac16_13.md.

## macOS support window (verify against Apple's security releases)

Do not infer support from version arithmetic alone. Check Apple's current security
releases when this table may be stale. As of August 2026, Apple is publishing
security releases for macOS Tahoe 26, Sequoia 15, and Sonoma 14; Monterey's
last security release was 12.7.6 on 2024-07-29.

| macOS | Status |
|---|---|
| 26 Tahoe | Receiving security patches ← **Mac16,13** |
| 15 Sequoia, 14 Sonoma | Receiving security patches |
| 13 Ventura | EOL |
| **12 Monterey and below** | **EOL — no security patches** ← **MacBookPro12,1** |

`macos:` showing 12.x **on the MacBookPro12,1 profile** → **CRITICAL security
risk**. Since it cannot be upgraded through Apple, mitigations are the response
(see below), not "update the OS". If that machine's state file already records
this as Accepted/Decided, report it as a known accepted risk rather than adding
a duplicate Pending item. On the Mac16,13 profile an outdated-but-supported
macOS is a normal WARNING with `softwareupdate` as the fix.

## Severity assignment

- **CRITICAL** — security exposure on a data-bearing machine: EOL OS *without* mitigations in place; **FileVault Off**; Gatekeeper / SIP / firewall disabled; credentials/exfil risk.
- **WARNING** — redundancy or meaningful degradation: ≥2 VPN clients; free disk <20%; sustained memory pressure (per-profile thresholds below); large number of outdated packages; orphan launch daemons; discontinued app still installed.
- **INFO** — housekeeping: outdated formulae (routine), oversized caches (cleanup opportunity), long uptime (reboot suggested), minor cruft.

## Metric thresholds

Load, disk, and swap-growth logic are common; absolute memory numbers differ by
RAM size — use the column for the profile's RAM.

| Metric (from output) | 8 GB (MBP12,1) | 24 GB (Mac16,13) |
|---|---|---|
| `load_per_core_1_5_15` | ≤1.0 INFO · 1.0–2.0 sustained WARNING · >2.0 sustained CRITICAL | same |
| `available_gb` | >2 INFO · 1–2 WARNING · <1 CRITICAL | >4 INFO · 2–4 WARNING · <2 CRITICAL |
| `compressed_gb` | <1 INFO · 1–2 WARNING · >2 CRITICAL | <4 INFO · 4–8 WARNING · >8 CRITICAL |
| `swap` used | <256 MB INFO · 256 MB–1 GB WARNING · >1 GB & growing CRITICAL | <1 GB INFO · 1–2 GB WARNING · >2 GB & growing CRITICAL |
| `free_pct_root` | >20% INFO · 10–20% WARNING · <10% CRITICAL | same |

**Judge load against the 5/15-min per-core values and `uptime`, not the 1-min
spike** — the check itself (and an agent running it) inflates instantaneous
load. A single sample above 1 is not actionable. Also read the trend: a high
15-minute value with much lower 1/5-minute values is a recovering load, not a
currently worsening one. macOS routinely fills RAM on a healthy box — `swap`
matters far more than raw `available_gb`.

## Domain-specific rules

### Perf
- The fixable levers here are **few**: quit top CPU/MEM hogs you don't need, reduce browser tab/process count, reboot if uptime is long *and* load is high. Do **not** recommend "RAM cleaner" apps or purging — snake oil on macOS.
- Heavy hitters seen on the MacBookPro12,1: `claude`, multiple `Brave` processes, `Bitwarden`, `WindowServer`, `kitty`. Flag only if surprising.

### UI responsiveness
- On the MacBookPro12,1 (Intel/Iris 2015), Reduce Motion and Reduce Transparency are safe, reversible ways to reduce WindowServer compositing work. Treat them as INFO, not as a cure for CPU or RAM pressure. On the M4 they are pure preference — no perf framing.
- The low-risk Dock profile is: Scale minimize effect, launch animation off, recent apps off. Do not recommend undocumented ultra-short animation timings; they tend to make the UI feel broken and offer no sustained performance gain.
- Installed apps consume disk but not RAM merely by existing. Use the app footprint/last-use inventory to suggest candidates; never delete based on age metadata alone because Spotlight metadata can be incomplete.

### Disk
- `brew cleanup -n` reports space it *would* free → the skill runs `brew cleanup` for real (AUTO). Same for `brew autoremove` (removes orphaned dependencies — safe).
- On the MacBookPro12,1 the biggest historical lever is `~/Library/Application Support` — do **not** auto-delete; have the user inspect per-app subfolders only when disk is actually constrained. Print `du -sh ~/Library/Application\ Support/* | sort -rh | head` as a follow-up.
- Trash (`~/.Trash`), `~/Downloads`, `~/Desktop` are user data — suggest reviewing, never delete.

### Hygiene
- **VPN redundancy:** ≥2 VPN clients = WARNING labelled "review for consolidation", **not** "delete all but one". Reason: Tailscale/WireGuard are mesh/transport (LAN access, exit nodes) and serve a different role than a privacy VPN (Mullvad). Ask the user which role each fills before recommending removal. An *orphaned* VPN daemon (e.g. `net.mullvad.daemon` with no matching app) is unambiguous cruft → safe to remove.
- **Discontinued apps:** Boxcryptor (EOL 2023, discontinued after Dropbox acquisition) → remove if unused (its daemon is an orphan too). Flash Player / `JavaAppletPlugin.plugin` → security risk, remove. Oracle Java → if nothing needs it, remove; if needed, prefer Temurin (`brew install --cask temurin`) over Oracle.
- **Orphan launch daemons** (`ORPHAN ... binary missing`): the app was uninstalled but its plist remains. Safe to remove — needs `sudo` for `/Library/LaunchDaemons` (MANUAL). Command template: `sudo launchctl bootout system <plist> ; sudo rm <plist>` (and the matching `~/Library/LaunchAgents` variant without sudo). `app-mgd` / `ok` lines are not actionable.
- **Stale helpers** (`STALE? ... owner app missing`): the privileged helper still exists but its expected GUI app is absent. Ask whether the user still needs the product before removal. If not, remove its plist and exact helper binary as a MANUAL action; warn that reinstalling the app will be required to restore the helper.
- **brew outdated:** routine → INFO. Per profile: on **MacBookPro12,1** do **not** suggest blanket `brew upgrade` (no monterey bottles → forbidden source builds; `--force-bottle` wrapper in `~/.zshrc`); verify bottle availability and propose a targeted command instead. On **Mac16,13** blanket `brew upgrade` is acceptable (arm64 bottles) but stays MANUAL. `brew missing` empty = good.

### Security
- **FileVault Off → CRITICAL** on either machine. Action is MANUAL and must warn: `fdesetup enable` encrypts in the background for hours; keep the machine plugged in and awake until done; **save the recovery key**. On the MacBookPro12,1's near-full 11-yo SSD, confirm free space first. Respect a recorded per-machine decision not to enable it — but a decision recorded on the OTHER machine does not apply.
- Gatekeeper `assessments enabled`, SIP `enabled`, firewall `enabled` = good (no action). Any of these off → WARNING/CRITICAL.
- `softwareupdate --schedule` on = good.
- **EOL OS mitigations** (the response to "cannot upgrade", MacBookPro12,1 only): verify that the browser vendor still supports Monterey before calling it current, remove unused/old software (shrinks attack surface), keep firewall + Gatekeeper on, and note the machine should be on a replacement timeline.

## Auto vs manual (the autonomy line)

**AUTO — the skill runs these directly, then reports what it freed/removed:**
- `brew cleanup` (frees cache / old versions)
- `brew autoremove` (removes orphaned dependencies)

**MANUAL — the skill prints the exact command with a one-line risk note, adds to the machine's `state/<model>.md` `Pending`, does NOT run:**
- App uninstall (`rm -rf /Applications/X.app`; recommend AppCleaner for full removal)
- Launch daemon removal (`sudo launchctl bootout … ; sudo rm …`)
- `brew upgrade` (version churn)
- Deleting caches beyond Homebrew's
- `fdesetup enable` (FileVault)

If anything is ambiguous or could touch user data, default to MANUAL.
