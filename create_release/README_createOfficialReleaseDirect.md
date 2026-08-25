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
| `-o, --create-owp-branch` | After a successful release, also create and push `ngwpc-<release>` (or `ngwpc-<release>-pw` under PW) from the release tag's exact commit. This is what gets submitted as a PR to the upstream NOAA OWP parent repo; the script only prepares and pushes the branch — it does not open that PR. | off |
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
createOfficialReleaseDirect.sh --create-owp-branch
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

1. Resolves `repo_directory` and confirms it exists.
2. Prompts **(C)ontinue / (S)kip / (Q)uit** (60s timeout, defaults to Continue).
   - `Q` aborts the entire run (remaining repos are not processed).
3. Confirms `gh` can see the repo and reads the `origin` remote.
4. Checks the remote for an existing tag matching the release number; if
   found, the repo is skipped as `FAILED (tag exists)` — releases are never
   overwritten.
5. Checks out and fast-forward pulls the selected development branch
   (`git checkout` + `git pull --ff-only`). If the branch can't be updated,
   the repo is skipped as `FAILED (pull failed)`.
6. Creates the GitHub release (`gh release create`) targeting that branch,
   tagged with the release number, with notes (+ commit summary if given).
7. If `-o/--create-owp-branch` was passed and the release succeeded: fetches
   the new tag, creates `ngwpc-<release>[-pw]` from that tag's exact commit
   (not branch HEAD, which may have moved on since), and pushes it to
   `origin`. Skipped with an error if that branch already exists remotely.
   A failure here does not roll back the release.

Before processing begins, the script prints the full list of repos with
their resolved status (will run / skipped, and why), and asks for a final
`Y/N` confirmation.

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
- The per-repo prompt lets you bail out (`Q`) before any release is created
  for a given repo; already-completed repos in the same run are unaffected.
