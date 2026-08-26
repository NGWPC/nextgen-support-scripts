# createOfficialReleaseDirect.sh

Creates an **OFFICIAL** GitHub release directly off the `development` (or
`development-pw`) branch for every repository listed in a JSON config file,
using the release number and notes already in that file.

There is no RC step, no `ngwpc-candidate`/`ngwpc-release` branches, and no
pull requests — this tags and releases whatever is currently on the selected
development branch, as-is. Submodule pointers are **not** updated.

## Requirements

- `git`, `jq`, and the GitHub CLI (`gh`), authenticated (`gh auth login`)
- Push access to each repo's `origin`, and (if using `-o`) permission to
  create branches on `origin`
- A `createReleaseConfig.json` (or equivalent) in the current directory

## Usage

```
createOfficialReleaseDirect.sh [OPTIONS]
```

| Option | Description | Default |
|---|---|---|
| `-c, --config FILE` | Configuration JSON file | `createReleaseConfig.json` |
| `-e, --environment ENV` | Branch/release environment: `STANDARD` or `PW` | `STANDARD` |
| `-o, --create-owp-branch` | **Standalone step — does NOT create a release.** Creates and pushes OWP branch(es) from *already-existing* release tag(s). Requires that the release/tag(s) were already created by a prior, separate run of this script **without** `-o`. This is what gets submitted as a PR to the upstream NOAA OWP parent repo; the script only prepares and pushes the branch — it does not open that PR. Behavior depends on whether `-e` is also given — see [OWP branch modes](#-o-owp-branch-modes) below. | off |
| `-v, --verbose` | Print the exact `gh` commands being executed | off |
| `-h, --help` | Display usage and exit | — |

### Environment branches / tags

| Environment | Branch | Example tag |
|---|---|---|
| `STANDARD` | `development` | `10.2` |
| `PW` | `development-pw` | `10.2-pw` |

### Examples

```
createOfficialReleaseDirect.sh
createOfficialReleaseDirect.sh --config createReleaseConfig.json
createOfficialReleaseDirect.sh --environment PW --config createReleaseConfig_pass1_pw.json

# Two-step OWP flow: create the release(s) first, then the branch(es).
createOfficialReleaseDirect.sh
createOfficialReleaseDirect.sh --environment PW
createOfficialReleaseDirect.sh --create-owp-branch   # auto: per-repo env decides
```

## Config file

A top-level JSON array. Each entry:

| Field | Required | Description |
|---|---|---|
| `repo_directory` | yes | Local path to the repo (`~` is expanded) |
| `release` | yes | Base release number, e.g. `"10.2"` (the script appends `-pw` under PW) |
| `release_notes` | no | Release notes body |
| `commit_summary` | no | If present, appended to the notes under a "Commit Summary" heading |
| `skip` | no | `true` to always skip this entry, regardless of `env` |
| `env` | no | `PW`, `AWS`, or `ALL` (default `ALL`) — controls which `-e` run this repo is processed under (independent of `skip`) |

`env` filtering:
- `-e PW` → repo runs only if `env` is `PW` or `ALL`
- `-e STANDARD` → repo runs only if `env` is `AWS` or `ALL`

Invalid `env` values (anything other than `PW`/`AWS`/`ALL`) abort the run
during config validation, before any repo is touched.

## What it does, per repository

Steps 1–3 are the same regardless of mode:

1. Resolves `repo_directory` and confirms it exists.
2. Prompts **(C)ontinue / (S)kip / (Q)uit** (60s timeout, defaults to Continue).
   - `Q` aborts the entire run (remaining repos are not processed).
3. Confirms `gh` can see the repo and reads the `origin` remote.

From there, the script runs in one of two mutually exclusive modes:

### Normal mode (no `-o`) — create the release

4. Checks the remote for an existing tag matching the release number; if
   found, the repo is skipped as `FAILED (tag exists)` — releases are never
   overwritten.
5. Checks out and fast-forward pulls the selected development branch
   (`git checkout` + `git pull --ff-only`). If the branch can't be updated,
   the repo is skipped as `FAILED (pull failed)`.
6. Creates the GitHub release (`gh release create`) targeting that branch,
   tagged with the release number, with notes (+ commit summary if given).

No OWP branch is created in this mode, even if the release succeeds.

### `-o` / `--create-owp-branch` mode — standalone branch step

This mode **never creates a release**. Run it as a separate, later
invocation after the release/tag(s) already exist from a normal-mode run.
It has two sub-modes, depending on whether `-e`/`--environment` is also
given:

<a name="-o-owp-branch-modes"></a>
**`-e` given (single pass):** processes each repo once, same `env`
filtering as release mode (`repo_env_applies`), creating only the branch
for that one environment (`ngwpc-<release>` under STANDARD, or
`ngwpc-<release>-pw` under PW).

**`-e` NOT given (auto, per-repo env):** for each non-skipped repo, the
repo's own `env` field decides which branch(es) get created, independent
of any command-line environment — the same repo can produce up to two
branches in one invocation:

| Repo's `env` | Branch(es) created |
|---|---|
| `AWS` | `ngwpc-<release>` only |
| `PW` | `ngwpc-<release>-pw` only |
| `ALL` | both `ngwpc-<release>` and `ngwpc-<release>-pw` |

Each branch attempt still requires its corresponding release tag to
already exist (`10.2` for the STANDARD/AWS branch, `10.2-pw` for the PW
branch) — a repo with `env=ALL` where only the STANDARD tag exists will
successfully create `ngwpc-10.2` and fail (`tag not found`) for the `-pw`
branch, independently. The summary table shows each attempt as its own row
(suffixed `[STANDARD]` / `[PW]`) so both outcomes are visible.

Steps, per repo (per environment, in auto mode):

4. Checks the remote for a tag matching that environment's release number;
   if it's **missing**, that attempt is recorded as `FAILED (tag not
   found)` — you must create that release first.
5. Fetches that tag, then creates `ngwpc-<release>[-pw]` from the tag's
   exact commit (not branch HEAD, which may have moved on since the
   release was made), and pushes it to `origin`. Skipped with an error if
   that branch already exists remotely.
6. Returns to whatever branch/ref was checked out before this step.

`skip: true` on a repo entry always skips it entirely, regardless of `env`
or which `-o` sub-mode is active.

Before processing begins (any mode), the script prints the full list of
repos with their resolved status (will run / skipped, and why — including,
in auto mode, exactly which branch(es) each repo will attempt), and asks
for a final `Y/N` confirmation.

## Output

- **Console + log file**: `createOfficialReleaseDirect_<timestamp>.log`
  (colors stripped) capturing everything printed during the run.
- **Summary table**, printed at the end and saved to
  `release_summary_direct.txt`: repo, release tag, status
  (`SUCCESS`/`FAILED`/`SKIPPED`/`QUIT`), elapsed time, and resulting commit
  hash.
- **Exit code**: `0` on full success, `2` if the user chose Quit mid-run,
  otherwise the last non-zero return code encountered.

## Safety notes

- Never overwrites an existing release tag — it fails closed and skips.
- Never merges branches, opens PRs, or touches submodule pointers.
- `-o` is fully decoupled from release creation: it can only ever create an
  OWP branch from a tag that already exists, and it will refuse to run if
  that tag isn't there yet.
- In auto per-repo-env mode, a repo's two branch attempts (STANDARD/PW) are
  independent — a failure on one (e.g. missing PW tag) never blocks or
  rolls back the other.
- The per-repo prompt lets you bail out (`Q`) before any action is taken
  for a given repo; already-completed repos in the same run are unaffected.
