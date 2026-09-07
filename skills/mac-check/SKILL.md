---
name: mac-check
description: Health check, cleanup, and optimization advice for this Mac. Diagnoses performance, disk, software hygiene, and security; runs safe cleanups automatically; prints exact commands for anything destructive. Use when the user runs /mac-check, or the weekly automated run fires.
disable-model-invocation: true
---

# /mac-check — Mac health check & maintenance assistant

You maintain the user's Macs — one shared `~/mac-ops` repo, one state file per
machine. Identify THIS machine from the `model:` line of the checks.sh META
section and pick its profile in `CHECKS.md` (known: `MacBookPro12,1` and
`Mac16,13`). The job: gather machine state with a **tight**,
deterministic script, render a **verdict** per `CHECKS.md`, run the cleanups
that are safe to run, and queue everything else as ready-to-paste commands in
the state file. Never wing the diagnostics — the script is the source of truth.

## Step 0 — decide the mode

- **Interactive** (default): the user ran `/mac-check`. You may ask one focused
  question if a finding is ambiguous, and you offer to act on pending items.
- **Weekly / headless**: the run was invoked with the `weekly` argument, or env
  `MAC_CHECK_HEADLESS=1` is set. **No questions, ever.** Do safe cleanups, write
  the report + STATE, send a macOS notification, exit.

Note: the *automated* weekly job is a separate pure-bash runner
(`~/mac-ops/scripts/mac-check-weekly.sh`, triggered by launchd) — it does NOT
invoke this skill. This `weekly` mode is only for manual non-interactive runs.

Completion criterion: you know which mode you're in before touching anything.

## Step 1 — read state (or bootstrap)

The state file is per-machine: `~/mac-ops/state/$(sysctl -n hw.model | tr ',' '_').md`
(`MacBookPro12_1.md` = MBP 2015, `Mac16_13.md` = Air M4). Read THIS machine's
file. If the repo exists but the file does not, create it from the template at
the end of this file. If `~/mac-ops` itself does not exist, **bootstrap** the
repo first:

```bash
git init -q ~/mac-ops
mkdir -p ~/mac-ops/state ~/mac-ops/reports ~/mac-ops/scripts
# write state/<model>.md, .gitignore (see end of this file for templates)
git -C ~/mac-ops add -A && git -C ~/mac-ops commit -qm "init mac-ops"
```

State is how you get **continuity**: a finding already listed under `Pending`,
`Decisions`, or `Accepted` is **not new** — don't re-announce it as a discovery.
Show it as "still pending" or "you already decided X" instead. Decisions
recorded on ANOTHER machine's state file do not carry over.

Completion criterion: this machine's `state/<model>.md` exists and you've read
its Pending / Decisions / Accepted sections.

## Step 2 — gather facts (the tight loop)

Run the script and capture full output. It is strictly read-only:

```bash
LC_ALL=C /bin/bash ~/.claude/skills/mac-check/checks.sh
```

Do **not** improvise extra diagnostic commands of your own — if something is
missing, the right fix is to extend the script, not to freelance. The script is
the single source of truth for machine state.

If core telemetry is reported as `unavailable` because the agent sandbox denies
`sysctl`, `ps`, `fdesetup`, or `softwareupdate`, rerun this exact script with
read-only elevated execution. Do not interpret placeholder or restricted data
as a real machine finding.

Completion criterion: you have the script's full sectioned output in front of you.

## Step 3 — render the verdict

Load `~/.claude/skills/mac-check/CHECKS.md` and apply it to the output. For each
notable item assign a **severity** (CRITICAL / WARNING / INFO) using the
thresholds and rules there, and classify each as **auto** (you run it) or
**manual** (you print the command). Weight security findings heavily — these
are data-bearing machines, and on the MacBookPro12,1 profile the EOL OS makes
security the priority domain.

Completion criterion: every notable finding has a severity and an auto/manual tag.

## Step 4 — run the auto cleanups

These two are safe and are the only mutations you perform unprompted. Run them
and capture what changed:

```bash
brew cleanup
brew autoremove
```

Record space freed and anything removed (you'll put this in `History`).

Completion criterion: both ran; you know what they freed/removed.

## Step 5 — assemble manual actions

For every **manual** finding, produce the exact command plus a one-line risk
note (from CHECKS.md's auto-vs-manual table). Examples of the shape:

- Orphan daemon: `sudo launchctl bootout system /Library/LaunchDaemons/X.plist ; sudo rm /Library/LaunchDaemons/X.plist` — *removes leftover daemon of an uninstalled app; needs sudo.*
- App removal: drag to Trash, or `rm -rf /Applications/X.app` (recommend AppCleaner for full cleanup).
- FileVault: `fdesetup enable` — *encrypts the disk over hours; keep plugged in & awake, save the recovery key.*

Completion criterion: each manual finding has a copy-paste command + risk note.

## Step 6 — write the report and update state

1. Write `~/mac-ops/reports/<model>/<YYYY-MM-DD>.md` (same model key as the
   state file): the full `checks.sh` output verbatim
   (this is the raw snapshot for drift), plus your findings table and what the
   auto-cleanups freed.
2. Update `~/mac-ops/state/<model>.md`:
   - `Last check:` line → today + mode.
   - `History` → prepend today's auto-cleanup result.
   - `Pending` → add **new** manual items only (severity + date), deduped against
     what's already there. Mark resolved ones `[x]`.
3. Commit:
   ```bash
   git -C ~/mac-ops add -A && git -C ~/mac-ops commit -qm "check $(date +%Y-%m-%d)"
   ```

Completion criterion: report file written; STATE.md updated and committed.

## Step 7 — report back

**Interactive:** print a compact findings table (severity · finding · action),
then the manual commands grouped by severity, then `→ added N to STATE.md
Pending`. Offer: "want me to walk through the pending items one by one?" Don't
act on anything destructive without explicit per-item go-ahead.

**Weekly / headless:** send a notification and stop:
```bash
osascript -e 'display notification "Mac check done: <C> critical, <W> warnings. <N> pending in ~/mac-ops/STATE.md" with title "mac-check"'
```
Summarize counts in the notification text. Do not print a wall of text nobody is
reading — the report file is the record.

Completion criterion: the user (or the notification) knows the run happened and
where to look.

---

## Templates

### `~/mac-ops/state/<model>.md` (initial; `<model>` = `sysctl -n hw.model | tr ',' '_'`)

```markdown
# Mac Ops State — <hw.model>
Last check: —
Machine: <hw.model> · <macOS version> · <RAM>

## Pending — manual actions
<!-- [ ] [SEVERITY] description — `command` -->

## Decisions — resolved
<!-- [x]/[-] YYYY-MM-DD decision -->

## Accepted — known limits

## History — cleanups
<!-- YYYY-MM-DD: what was cleaned/freed -->
```

### `~/mac-ops/.gitignore`

```
.DS_Store
.scratch/
logs/
```
