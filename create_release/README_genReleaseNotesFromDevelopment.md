# genReleaseNotesFromDevelopment.py

Generates release notes for multiple Git repositories from the commits on a branch (default: `development`) made **after** each repository's previous release tag.

Unlike `genReleaseNotes.py`, which diffs two existing tags (`previous_release_tag..release`), this script does **not** require the new release tag to exist. It is intended for generating notes *before* the release is created (e.g., before running `createOfficialReleaseDirect.sh`), so the output can be placed in the config's `release_notes` field.

## Requirements

- Python 3.7+
- `git` on `PATH`
- Local clones of each repository listed in the config, with `origin` pointing to GitHub
- Network access to `origin` (the script fetches and pulls)

No third-party Python packages are required.

## Usage

```bash
python3 genReleaseNotesFromDevelopment.py -c <config.json> <output option> [--branch BRANCH]
```

### Options

| Option | Description |
|---|---|
| `-c`, `--config FILE` | **Required.** JSON configuration file (same format as `createReleaseConfig*.json`). |
| `--branch BRANCH`, `--checkout-branch BRANCH` | Branch to check out, pull, and collect commits from. Default: `development`. |
| `--output FILE` | Markdown output. Adds `.md` if `FILE` has no extension. |
| `--output_md FILE` | Markdown output; extension forced to `.md`. |
| `--output_txt FILE` | Plain-text output; extension forced to `.txt`. |
| `--output_both FILE` | Writes both `FILE.md` and `FILE.txt`. |
| `-h`, `--help` | Show help and exit. |

Exactly one output option is required.

### Examples

```bash
# Markdown and text notes from development
python3 genReleaseNotesFromDevelopment.py \
  -c createReleaseConfig_FinalCodeDelivery_20260930.json \
  --output_both FinalCodeDelivery_20260930_notes

# Markdown only, from a different branch
python3 genReleaseNotesFromDevelopment.py \
  -c createReleaseConfig.json \
  --output_md notes \
  --branch development-pw
```

## Configuration

The config is a JSON array with one object per repository. Fields read by this script:

| Field | Required | Description |
|---|---|---|
| `repo_directory` | Yes | Path to the local clone. `~` is expanded. |
| `previous_release_tag` | No | Tag of the prior release. Commits after this tag's date are included. If empty or absent, the entire branch history is used. |
| `release` | No | New release name. Displayed in the output only; the tag does not need to exist. |
| `release_notes` | No | Displayed in the output's "Release Notes" line. |
| `skip` | No | If `true`, the repository is skipped. |

Other fields (e.g., `env`, `commit_summary`) are ignored.

### Example

```json
[
  {
    "repo_directory": "~/repos/ngen",
    "release": "FinalCodeDelivery_20260930",
    "previous_release_tag": "3.1.2.4.0",
    "release_notes": ""
  },
  {
    "repo_directory": "~/repos/ngen-forcing",
    "release": "FinalCodeDelivery_20260930",
    "previous_release_tag": "3.1.2.4.0",
    "release_notes": "",
    "skip": true
  }
]
```

## What the script does

For each repository not marked `skip`:

1. Checks out `--branch` (default `development`) if it isn't already checked out. A failed checkout (e.g., uncommitted changes that conflict) stops the script.
2. Runs `git fetch --all --tags --prune`.
3. Runs `git pull --ff-only origin <branch>`. A non-fast-forward pull prints an error but does not stop the script; notes are then generated from the local branch as-is.
4. Looks up the date of `previous_release_tag`.
5. Collects the qualifying commits (see below).
6. Generates the Summary, Additions/Removals/Changes, and Commits sections.

### Commit selection

A commit on the branch is included when **all** of the following are true:

- It is not a merge commit (`--no-merges`).
- Its **committer date** is later than the previous release tag's date.
- It is not reachable from the previous release tag.
- Its subject does not start with `Merge branch` or `Merge pull request`.

The tag date is `%(creatordate)`: the **tagger date** for annotated tags, or the **commit date** for lightweight tags.

Date filtering is done in Python rather than with `git log --since`, because `--since` can stop walking history early when commit dates are out of order.

#### Limitation

A commit whose committer date is **earlier** than the previous tag, but which was merged into the branch **afterwards** via a true merge commit, is excluded. Rebased and squash-merged commits receive new committer dates and are included correctly.

## Output

The Markdown file starts with a dated title and a table of contents, followed by one section per repository:

```markdown
## ngen
- **Release Notes**:
- **Release Version**: `FinalCodeDelivery_20260930`
- **Source Branch**: `development`
- **Release Commit SHA**: `528f0e9cdb2481efc0a35aaf84a671721858d036`
- **Previous Release**: `3.1.2.4.0`
- **Previous Release Date**: `2026-03-01T00:00:00+00:00`

### Summary
Corrected unit conversions and size/type reporting. ...

- **Last Commit Hash**: `528f0e9cdb2481efc0a35aaf84a671721858d036`
- **Last Commit Date**: `2026-05-01T00:00:00-07:00`

### Removals
- Removed unused, duplicate, obsolete, and deprecated code paths, ...

### Changes
- Corrected unit conversions and size/type reporting across ...

### Commits
- Remove unused helper (528f0e9)
- Fix unit conversion in bytes (482c82c)
```

The text file contains the same information with plain headings; the Summary paragraph is wrapped at 80 columns.

**Release Commit SHA** is the current tip of the branch after pulling, i.e., the commit that `createOfficialReleaseDirect.sh` will tag if nothing is pushed in the meantime.

### Generated sections

- **Summary**: one paragraph of up to five themes, chosen by how many commits match each theme's keywords and by theme priority. Followed by the full hash and committer date (ISO 8601) of the most recent commit included in the notes, or `N/A` if there are none.
- **Additions / Removals / Changes**: one summary sentence per matched theme. Commits that match no theme are rolled up into one "additional release updates" sentence per section (up to five items each).
- **Commits**: the raw commit subjects with short SHAs, unfiltered by theme.

Low-value commits (merges, rebases, WIP, formatting, typos, comments, TODOs) are excluded from the Summary and section sentences but still appear under Commits.

Theme keywords and sentences are defined in `SUMMARY_THEME_RULES` and `SECTION_THEME_RULES` and are identical to `genReleaseNotes.py`.

### Special cases

| Situation | Result |
|---|---|
| No qualifying commits | Commits shows `No commits found.` |
| `previous_release_tag` not found in the repo | The repo's section shows `ERROR: Previous release tag '<tag>' not found in repository.` Other repositories are still processed. |
| `previous_release_tag` empty or absent | All non-merge commits on the branch are used. |
| `repo_directory` does not exist | The script stops with an error. |

## Typical workflow

1. Update the config so `previous_release_tag` holds the last release and `release` holds the new one:
   ```bash
   jq 'map(.previous_release_tag = .release | .release = "FinalCodeDelivery_20260930")' \
     createReleaseConfig_FinalCodeDelivery_20260930.json > tmp.json \
     && mv tmp.json createReleaseConfig_FinalCodeDelivery_20260930.json
   ```
2. Generate the notes:
   ```bash
   python3 genReleaseNotesFromDevelopment.py \
     -c createReleaseConfig_FinalCodeDelivery_20260930.json \
     --output_both FinalCodeDelivery_20260930_notes
   ```
3. Review and edit the output, then copy each repository's notes into its `release_notes` field.
4. Create the releases:
   ```bash
   ./createOfficialReleaseDirect.sh -c createReleaseConfig_FinalCodeDelivery_20260930.json
   ```

## Differences from genReleaseNotes.py

| | genReleaseNotes.py | genReleaseNotesFromDevelopment.py |
|---|---|---|
| Default branch | `ngwpc-release` | `development` |
| Commit range | `previous_release_tag..release` (both tags must exist) | Commits on the branch after the previous tag's date, excluding those reachable from it |
| New release tag | Must exist | Need not exist |
| Release Commit SHA | Commit the release tag points to | Current tip of the branch |
| Hotfix tag lookup (`find_latest_patch_tag`) | Present | Not used |
| Pull | `git pull origin <branch>` | `git pull --ff-only origin <branch>` |
| Missing previous tag | `git log` error; commits may be empty | Per-repo ERROR line; other repos continue |
