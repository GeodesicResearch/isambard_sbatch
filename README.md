# isambard_sbatch

A drop-in `sbatch` wrapper that enforces a project-wide node limit on SLURM clusters. Before every submission, it checks how many nodes the project is currently using (running + pending) and blocks the job if the configured cap would be exceeded.

The check is **account-wide**: all users in the configured SLURM account share the same cap. This prevents any single project from accidentally monopolizing the cluster.

## Quick Start

```bash
# Install (one-time)
git clone https://github.com/GeodesicResearch/isambard_sbatch.git ~/isambard_sbatch
bash ~/isambard_sbatch/install.sh
source ~/.bashrc

# Submit jobs — the node limit is enforced automatically (default: 256 nodes)
isambard_sbatch --nodes=16 pretrain_neox.sbatch /path/to/config.yml
```

## Installation

### Requirements

- Bash 4.0+
- SLURM (`sbatch`, `squeue` in PATH)
- A SLURM account to monitor (default: `brics.a5k`)

### Install

```bash
cd ~/isambard_sbatch
bash install.sh
source ~/.bashrc
```

The installer:
1. Makes `bin/isambard_sbatch` and `bin/sbatch` executable
2. Prepends `~/isambard_sbatch/bin` to `$PATH` in your `.bashrc` (or `.bash_profile` / `.zshrc`)
3. Adds an `alias sbatch='isambard_sbatch'` for interactive shells
4. Sets default values for `ISAMBARD_SBATCH_MAX_NODES` and `ISAMBARD_SBATCH_ACCOUNT`

After installation, both `sbatch` and `isambard_sbatch` route through the wrapper. The real `sbatch` (at `/usr/bin/sbatch`) is called automatically once the limit check passes.

Running `install.sh` multiple times is safe — it detects an existing installation and skips.

### Install for Other Users

Each user who wants the node cap should clone the repo to their home and run the installer:

```bash
git clone https://github.com/GeodesicResearch/isambard_sbatch.git ~/isambard_sbatch
bash ~/isambard_sbatch/install.sh
source ~/.bashrc
```

To update to the latest version:

```bash
cd ~/isambard_sbatch && git pull
```

The installer resolves paths relative to wherever it's run from, so each user's `.bashrc` will point to their own copy.

### Uninstall

```bash
bash ~/isambard_sbatch/uninstall.sh
source ~/.bashrc
```

This removes all `isambard_sbatch` lines from your shell config. `sbatch` reverts to the system binary at `/usr/bin/sbatch`. The `~/isambard_sbatch` directory is left in place; remove it manually if desired:

```bash
rm -rf ~/isambard_sbatch
```

Running `uninstall.sh` when already uninstalled is safe — it reports "nothing to uninstall" and exits.

## Usage

After installation, use `isambard_sbatch` to submit jobs. The wrapper is transparent when the project is under its node limit:

```bash
isambard_sbatch --nodes=16 pretrain_neox.sbatch config.yml
```

All arguments are passed through to the real `sbatch` unmodified. The wrapper only inspects `--nodes` / `-N` to determine how many nodes the job requests.

> **Note:** An `sbatch` alias and PATH shim are also installed so that bare `sbatch` calls go through the wrapper too. However, prefer calling `isambard_sbatch` explicitly — it makes the intent clear and avoids surprises if the alias is overridden.

### When a Submission Is Blocked

If the project would exceed the configured cap, the submission is rejected with exit code 1 and a diagnostic message:

```
══════════════════════════════════════════════════════════════════
 isambard_sbatch: submission BLOCKED — project node limit exceeded
══════════════════════════════════════════════════════════════════

  Account:         brics.a5k
  Max nodes:       256  ($ISAMBARD_SBATCH_MAX_NODES)
  Currently used:  120 nodes (running + pending)
  Requested:       16 nodes
  Would total:     136 nodes

  To proceed, either:
    - Wait for existing jobs to complete or cancel pending ones
    - Increase limit: export ISAMBARD_SBATCH_MAX_NODES=<N>
    - Force this submission: ISAMBARD_SBATCH_FORCE=1 isambard_sbatch ...
══════════════════════════════════════════════════════════════════
```

The message shows exactly how much headroom is left so you can adjust.

## Configuration

All settings are environment variables. Set them in `.bashrc` for persistence or per-command for one-off overrides.

| Variable | Default | Description |
|----------|---------|-------------|
| `ISAMBARD_SBATCH_MAX_NODES` | `256` | Maximum total nodes (running + pending) for the account |
| `ISAMBARD_SBATCH_ACCOUNT` | `brics.a5k` | SLURM account to monitor via `squeue -A` |
| `ISAMBARD_SBATCH_FORCE` | `0` | Set to `1` to bypass the limit check for a single submission |
| `ISAMBARD_SBATCH_DISABLED` | `0` | Set to `1` to disable entirely (pass straight through to real sbatch) |
| `ISAMBARD_SBATCH_DRY_RUN` | `0` | Set to `1` to preview what would happen without actually submitting |
| `ISAMBARD_SBATCH_BAD_NODES_FILE` | `/projects/a5k/public/isambard_sbatch_bad_nodes.log` | Shared log of bad compute nodes to exclude |
| `ISAMBARD_SBATCH_BAD_NODES_TTL` | `604800` (7 days) | Seconds before a bad-node entry expires |

### Examples

```bash
# Override the cap (persistent — add to .bashrc)
export ISAMBARD_SBATCH_MAX_NODES=128

# Change which SLURM account is monitored
export ISAMBARD_SBATCH_ACCOUNT=brics.a5k

# Force a single submission past the limit
ISAMBARD_SBATCH_FORCE=1 isambard_sbatch --nodes=64 big_job.sbatch

# Disable for the rest of this shell session
export ISAMBARD_SBATCH_DISABLED=1

# Preview the limit check without submitting
ISAMBARD_SBATCH_DRY_RUN=1 isambard_sbatch --nodes=16 config.sbatch
# Output: [DRY RUN] Would submit: /usr/bin/sbatch --nodes=16 config.sbatch
#         [DRY RUN] Account=brics.a5k  Current=31  Requested=16  Max=256  Total=47
```

## Bad-Node Exclusion

The cluster occasionally has broken compute nodes — VS Code tunnels that never come up, jobs that crash immediately, etc. Because allocations can take hours to cycle through on a busy cluster, landing on a bad node is expensive. `isambard_sbatch` reads a shared list of known-bad nodes and automatically passes them to SLURM's `--exclude` flag on every submission.

### How it works

- A shared append-only log at `/projects/a5k/public/isambard_sbatch_bad_nodes.log` records bad nodes. Every team member can read and append.
- Each line is tab-separated: `<epoch>\t<node>\t<reason>\t<user>`.
- Entries expire after `ISAMBARD_SBATCH_BAD_NODES_TTL` seconds (default: 7 days), so a node that's been fixed stops being excluded automatically.
- On every submission, the wrapper reads the log, keeps lines still within the TTL window, dedupes the node list, and merges it with any `--exclude` you passed on the command line before handing control to real sbatch.
- Active in the main and `ISAMBARD_SBATCH_FORCE=1` paths. Skipped when `ISAMBARD_SBATCH_DISABLED=1` (transparent passthrough) and in `--check` (no submission).

### Mark a node as bad

```bash
isambard_sbatch --mark-bad nid001234 "vscode tunnel failed to come up"
```

The node name must match `^[A-Za-z0-9._-]+$`. Tabs and newlines are stripped from the reason. The file is created with group-writable perms if missing.

### List active bad nodes

```bash
isambard_sbatch --list-bad
#   2026-04-16 09:12:03  nid001234                 vscode tunnel failed          (alice)
#   2026-04-16 14:47:11  nid005678                 nccl timeout                  (bob)
```

Expired entries are hidden.

### Manual append

The file format is plain text, so you can append without the subcommand if you prefer:

```bash
printf '%s\t%s\t%s\t%s\n' "$(date +%s)" nid001234 "tunnel hung" "$USER" \
    >> /projects/a5k/public/isambard_sbatch_bad_nodes.log
```

A single `printf` under 4 KB is an atomic append on Linux `O_APPEND` files — multiple team members can append concurrently without locking.

### See what's being excluded on a submission

Every submission prints a two-line bad-nodes summary (count, TTL window, file path, and the `--mark-bad` hint):

```
  Bad nodes: 2 excluded (last 7d)  —  file: /projects/a5k/public/isambard_sbatch_bad_nodes.log
             report more: isambard_sbatch --mark-bad <node> [reason]
```

Use `ISAMBARD_SBATCH_DRY_RUN=1` to see the full command, including the injected `--exclude`:

```bash
ISAMBARD_SBATCH_DRY_RUN=1 isambard_sbatch --nodes=4 config.sbatch
# [DRY RUN] Would submit: /usr/bin/sbatch --nodes=4 config.sbatch --exclude=nid001234,nid005678
```

### Opt out

- Per-submission: `ISAMBARD_SBATCH_DISABLED=1 isambard_sbatch ...` bypasses the wrapper entirely.
- Use a local log: `export ISAMBARD_SBATCH_BAD_NODES_FILE=~/.my_bad_nodes.log`.
- Shorten the TTL: `export ISAMBARD_SBATCH_BAD_NODES_TTL=3600` (1 hour).

## Check Mode (`--check`)

The `--check` flag performs a lightweight node-limit check without submitting a job. It's designed for use inside sbatch scripts as a defense-in-depth guard — catching jobs that bypass the `isambard_sbatch` wrapper (e.g., submitted via raw `/usr/bin/sbatch`).

```bash
# Manual check
isambard_sbatch --check
# Output (stderr): isambard_sbatch --check: OK — account=brics.a5k using 42/256 nodes

# Use in an sbatch script (guard snippet)
if ! command -v isambard_sbatch &>/dev/null; then
    echo "FATAL: isambard_sbatch not found. Install: ~/isambard_sbatch/install.sh" >&2
    scancel "$SLURM_JOB_ID" 2>/dev/null; exit 1
fi
if ! isambard_sbatch --check; then
    scancel "$SLURM_JOB_ID" 2>/dev/null; exit 1
fi
```

**Behavior:**
- Queries current account-wide node usage (running + pending)
- If `current > ISAMBARD_SBATCH_MAX_NODES`: prints `BLOCKED`, exits 1
- If under: prints `OK`, exits 0
- Respects `ISAMBARD_SBATCH_FORCE` (exits 0 when forced)
- **Ignores** `ISAMBARD_SBATCH_DISABLED` — the guard is a separate defense layer from the wrapper's pass-through mode
- Does **not** invoke sbatch, does **not** parse node arguments

### Guard Snippet

All sbatch scripts in the project include a guard snippet immediately after the `#SBATCH` directives. This ensures the node limit is enforced even if someone calls `/usr/bin/sbatch` directly:

```bash
# --- Isambard node-limit guard (do not remove) ---
if ! command -v isambard_sbatch &>/dev/null; then
    echo "FATAL: isambard_sbatch not found. Install: ~/isambard_sbatch/install.sh" >&2
    scancel "$SLURM_JOB_ID" 2>/dev/null; exit 1
fi
if ! isambard_sbatch --check; then
    scancel "$SLURM_JOB_ID" 2>/dev/null; exit 1
fi
```

The guard:
1. **Fails hard** if `isambard_sbatch` is not installed (cancels the job and exits)
2. **Cancels the job** if the account is over the node limit
3. Uses `if !` pattern which is safe with `set -e`

## How It Works

On every `isambard_sbatch` invocation:

1. **Parse the requested node count.** Checks command-line arguments first (`--nodes=N`, `--nodes N`, `-N N`, `-NN`). If not on the CLI, reads `#SBATCH` directives from the batch script. Defaults to 1 if not specified anywhere.

2. **Query current account usage.** Runs `squeue -A <account> -t RUNNING,PENDING` and sums the node counts across all users in the account. Both running and pending jobs are counted, since pending jobs represent committed allocations that will use nodes once resources are available.

3. **Enforce the limit.** If `current_nodes + requested_nodes > ISAMBARD_SBATCH_MAX_NODES`, the submission is blocked (exit code 1) with a diagnostic message.

4. **Pass through to real sbatch.** If the check passes, `exec /usr/bin/sbatch "$@"` is called with all original arguments, so the behavior is identical to calling sbatch directly.

### Why Count Pending Jobs?

Pending jobs don't use nodes yet, but they represent your project's commitment to use them. Without counting pending jobs, a user could submit hundreds of large jobs while the cluster is busy, and they'd all start simultaneously once resources free up — defeating the purpose of the cap. If your pending jobs are blocking new submissions, cancel the ones you no longer need with `scancel`.

### Node Count Parsing

The wrapper handles all standard sbatch formats:

**Command-line arguments (checked first, take precedence):**

| Format | Example |
|--------|---------|
| `--nodes=N` | `isambard_sbatch --nodes=16 script.sh` |
| `--nodes N` | `isambard_sbatch --nodes 16 script.sh` |
| `-N N` | `isambard_sbatch -N 16 script.sh` |
| `-NN` | `isambard_sbatch -N16 script.sh` |

**Batch script directives (used as fallback):**

| Format | Example |
|--------|---------|
| `#SBATCH --nodes=N` | `#SBATCH --nodes=16` |
| `#SBATCH -N N` | `#SBATCH -N 16` |
| `#SBATCH -NN` | `#SBATCH -N16` |

**Node ranges** like `--nodes=2-8` are resolved to the maximum value (8), since SLURM may allocate up to that many.

If multiple `--nodes` / `-N` appear in the same context (e.g., two `#SBATCH --nodes=` lines), the last one wins, matching real sbatch behavior. CLI always overrides script directives.

### PATH Shadowing

The installer places `~/isambard_sbatch/bin` at the front of `$PATH`. This directory contains:

- **`isambard_sbatch`** — the main wrapper script with all the logic
- **`sbatch`** — a thin 2-line wrapper that calls `isambard_sbatch`

Because `~/isambard_sbatch/bin` appears before `/usr/bin` in `$PATH`, both the `sbatch` command and `isambard_sbatch` command route through the wrapper. This works in scripts, cron jobs, and non-interactive shells — not just interactive terminals where aliases apply.

The wrapper finds the real sbatch by scanning `$PATH` entries that aren't its own directory, falling back to `/usr/bin/sbatch`.

## File Structure

```
~/isambard_sbatch/
├── bin/
│   ├── isambard_sbatch      # Main wrapper (argument parsing, limit check, submission)
│   └── sbatch           # Thin wrapper that calls isambard_sbatch (shadows /usr/bin/sbatch)
├── install.sh           # Adds to PATH + alias in .bashrc
├── uninstall.sh         # Removes from .bashrc, restores system sbatch
├── tests/
│   └── run_tests.sh     # Unit tests + integration tests
└── README.md
```

## Tests

```bash
bash ~/isambard_sbatch/tests/run_tests.sh
```

The test suite includes:

**Unit tests** (no SLURM needed):
- Node count parsing from CLI arguments (`--nodes=N`, `--nodes N`, `-N N`, `-NN`)
- Node count parsing from `#SBATCH` directives in batch scripts
- Batch script file detection among mixed sbatch arguments
- Node range resolution (`2-8` -> `8`)
- CLI-overrides-script precedence

**Integration tests** (requires SLURM):
- Dry-run submissions that pass the limit check
- Dry-run submissions that are correctly blocked
- Blocking at exact capacity boundary
- Force bypass (`ISAMBARD_SBATCH_FORCE=1`)
- Disabled mode passthrough (`ISAMBARD_SBATCH_DISABLED=1`)
- Real job submission and cancellation
- The `sbatch` wrapper delegates to `isambard_sbatch`
- `--check` returns 0 when under limit, 1 when over
- `--check` respects `ISAMBARD_SBATCH_FORCE` but ignores `ISAMBARD_SBATCH_DISABLED`
- `--check` does not invoke sbatch
- Bad-node exclusion: fresh entries inject into `--exclude`; expired entries are ignored
- Bad-node exclusion: merges with user-supplied `--exclude`; preserves SLURM bracket expressions
- Bad-node exclusion: active under `FORCE`, skipped under `DISABLED` and `--check`
- `--mark-bad` / `--list-bad` subcommand roundtrip

## Troubleshooting

### "real sbatch not found in PATH"

The wrapper can't find `/usr/bin/sbatch`. Make sure SLURM is installed and `sbatch` is in your system PATH. On Isambard, this should always be available on both login and compute nodes.

### Limit seems too restrictive

Remember that **pending** jobs count toward the limit. Check what's queued:

```bash
squeue -A brics.a5k -t PENDING -o "%.10i %.30j %.4D %r"
```

Cancel jobs you no longer need to free up headroom:

```bash
scancel <job_id>
```

### I need to bypass the limit just once

```bash
ISAMBARD_SBATCH_FORCE=1 isambard_sbatch --nodes=64 urgent_job.sbatch
```

### I want to disable isambard_sbatch for a session without uninstalling

```bash
export ISAMBARD_SBATCH_DISABLED=1
# All sbatch calls now go straight to /usr/bin/sbatch
```

### Wrong account being checked

Verify your account name matches what SLURM uses:

```bash
sacctmgr show assoc where user=$USER format=Account%20 -n
```

Then set the correct one:

```bash
export ISAMBARD_SBATCH_ACCOUNT=brics.a5k
```
