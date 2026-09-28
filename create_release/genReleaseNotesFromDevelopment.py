#!/usr/bin/env python3
"""
Generate release notes from the commits on a development branch made after
the date of each repository's "previous_release_tag".

Unlike genReleaseNotes.py, the new release tag does not need to exist yet.
Commits are selected from the branch (default: development) when BOTH:
  - their committer date is later than the previous release tag's date, and
  - they are not already reachable from the previous release tag.

The previous tag's date is the tagger date for annotated tags, or the
commit date for lightweight tags.

Release-note prose is built from the commit subjects themselves:
  - commits are grouped by their own "Area: ..." prefix when they have one,
    otherwise by word-boundary keyword themes, otherwise into "other";
  - each commit subject is turned into a past-tense clause;
  - near-duplicate clauses (e.g. repeated pin bumps) are collapsed;
  - each group becomes one sentence built from its clauses.
No sentence is emitted unless commits in this delivery support it.
"""
import json
import shlex
import os
import argparse
import subprocess
import sys
from pathlib import Path
from datetime import datetime
import textwrap
import re
from collections import OrderedDict

# ---------------------------------------------------------
# Normalize output filename
# ---------------------------------------------------------
def normalize_output_filename(filename: str, mode: str) -> str:
    base, ext = os.path.splitext(filename)

    if mode == "default":
        return filename if ext else f"{filename}.md"
    elif mode == "md":
        return f"{base}.md"
    elif mode == "txt":
        return f"{base}.txt"
    else:
        raise ValueError(f"Unknown output mode: {mode}")

# ---------------------------------------------------------
# Shell runner
# ---------------------------------------------------------
def run(cmd, cwd=None, check=False):
    result = subprocess.run(
        cmd,
        cwd=cwd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    if result.returncode != 0:
        print(f"! Command failed: {cmd}")
        print(result.stderr)

        if check:
            raise RuntimeError(result.stderr)

    return result.stdout.strip()

# ---------------------------------------------------------
# Repo title
# ---------------------------------------------------------
def repo_title(path):
    return Path(path).name

# ---------------------------------------------------------
# Checkout branch before fetch/pull
# ---------------------------------------------------------
def checkout_branch(repo_dir, branch="development"):
    current_branch = run(
        "git rev-parse --abbrev-ref HEAD",
        cwd=repo_dir
    )

    if current_branch != branch:
        print(f"    Switching branch: {current_branch} -> {branch}")
        run(f"git checkout {branch}", cwd=repo_dir, check=True)
    else:
        print(f"    Already on branch: {branch}")

# ---------------------------------------------------------
# Tag / branch helpers
# ---------------------------------------------------------
def tag_exists(repo_dir, tag):
    """Return True if the tag exists locally (after fetch --tags)."""
    result = subprocess.run(
        ["git", "rev-parse", "-q", "--verify", f"refs/tags/{tag}"],
        cwd=repo_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    return result.returncode == 0


def get_tag_datetime(repo_dir, tag):
    """
    Return (unix_timestamp, iso_string) for a tag.

    %(creatordate) is the tagger date for annotated tags and the commit
    date for lightweight tags. Returns (None, None) if unavailable.
    """
    out = run(
        f"git for-each-ref --format='%(creatordate:unix) %(creatordate:iso-strict)' "
        f"{shlex.quote('refs/tags/' + tag)}",
        cwd=repo_dir
    )

    if not out:
        return None, None

    ts, iso = out.split(" ", 1)
    return int(ts), iso


def get_branch_head_sha(repo_dir, branch):
    """Return the full SHA at the tip of the branch."""
    sha = run(f"git rev-parse {shlex.quote(branch)}", cwd=repo_dir)
    return sha if sha else "Unknown"

# ---------------------------------------------------------
# Extract commits
# ---------------------------------------------------------
def get_commit_messages(repo_dir, branch, prev, prev_ts):
    """
    Return '<subject> (<short sha>)' for non-merge commits on `branch`
    whose committer date is after prev_ts and which are not reachable
    from the previous release tag.

    If prev is empty, all non-merge commits on the branch are returned.

    Also returns {"sha", "date"} for the most recent included commit,
    or None if there are none.

    Filtering by timestamp is done here rather than with `git log --since`,
    because --since can stop walking history early when commit dates are
    out of order.
    """
    cmd = f"git log {shlex.quote(branch)} --no-merges --format='%ct%x09%H%x09%cI%x09%s (%h)'"

    if prev:
        cmd += f" --not {shlex.quote('refs/tags/' + prev)}"

    output = run(cmd, cwd=repo_dir)

    commits = []
    last_commit = None

    for line in output.splitlines():
        parts = line.split("\t", 3)

        if len(parts) != 4:
            continue

        ts_str, full_sha, commit_iso, subject = parts

        try:
            ts = int(ts_str)
        except ValueError:
            continue

        if prev_ts is not None and ts <= prev_ts:
            continue

        if subject.startswith("Merge branch") or subject.startswith("Merge pull request"):
            continue

        # git log lists newest first, so the first kept commit is the last one.
        if last_commit is None:
            last_commit = {"sha": full_sha, "date": commit_iso}

        commits.append(subject)

    return (commits if commits else ["No commits found."]), last_commit

# =========================================================
# Release-note synthesis (commit-derived prose)
# =========================================================

NOISE_PATTERNS = [
    r"^merge\b",
    r"^merge pull request\b",
    r"^merge branch\b",
    r"^merged pr\b",
    r"\brebase\b",
    r"\bmerge resolution\b",
    r"^wip\b",
    r"\bformatting\b",
    r"^format\b",
    r"\blinting\b",
    r"\btypos?\b",
    r"\bdocstrings?\b",
    r"^(add|update|fix|remove)d? comments?\b",
    r"^(add|revise|update) todo\b",
]

# Phrases that are internal context rather than release content.
STRIP_PHRASES = [
    r"\s+per (the )?request (from|of|by) [A-Z][\w.-]*",
    r"\s*\(#\d+\)",
    r"\s+#\d+\b",
]

# Base verb -> past tense. Any of base, 3rd-person, or past form at the
# start of a commit subject is recognized as that verb.
VERB_PAST = {
    "add": "added", "update": "updated", "fix": "fixed", "bump": "bumped",
    "remove": "removed", "delete": "deleted", "drop": "dropped",
    "refactor": "refactored", "implement": "implemented", "create": "created",
    "enable": "enabled", "disable": "disabled", "parameterize": "parameterized",
    "parametrize": "parametrized", "pin": "pinned", "unpin": "unpinned",
    "move": "moved", "rename": "renamed", "replace": "replaced",
    "improve": "improved", "change": "changed", "introduce": "introduced",
    "use": "used", "correct": "corrected", "adjust": "adjusted",
    "allow": "allowed", "support": "supported", "integrate": "integrated",
    "convert": "converted", "revert": "reverted", "restore": "restored",
    "extend": "extended", "expand": "expanded", "simplify": "simplified",
    "upgrade": "upgraded", "downgrade": "downgraded", "migrate": "migrated",
    "handle": "handled", "ensure": "ensured", "prevent": "prevented",
    "avoid": "avoided", "include": "included", "document": "documented",
    "deprecate": "deprecated", "configure": "configured", "tweak": "tweaked",
    "reorganize": "reorganized", "modify": "modified", "make": "made",
    "build": "built", "deploy": "deployed", "tag": "tagged",
    "switch": "switched", "patch": "patched", "resolve": "resolved",
    "address": "addressed", "test": "tested", "verify": "verified",
    "validate": "validated", "increase": "increased", "decrease": "decreased",
    "reduce": "reduced", "skip": "skipped", "guard": "guarded",
    "rework": "reworked", "rewrite": "rewrote", "finalize": "finalized",
    "clarify": "clarified", "streamline": "streamlined", "sync": "synced",
    "align": "aligned", "consolidate": "consolidated", "set": "set",
    "split": "split", "expose": "exposed", "generate": "generated",
    "optimize": "optimized", "harden": "hardened", "relax": "relaxed",
    "tighten": "tightened", "standardize": "standardized", "raise": "raised",
    "lower": "lowered", "pass": "passed", "cleanup": "cleaned up",
}

# Verbs safe to convert when they appear mid-clause after "and" or a comma.
MID_CLAUSE_VERBS = {
    "add", "update", "fix", "remove", "parameterize", "bump", "rename",
    "replace", "improve", "refactor", "implement", "enable", "disable",
    "introduce", "delete", "upgrade", "migrate",
}

ADDITION_VERBS = {"added", "introduced", "created", "implemented", "enabled",
                  "exposed", "generated"}
REMOVAL_VERBS = {"removed", "deleted", "dropped", "deprecated", "unpinned"}


def _verb_forms(base):
    if base.endswith("y") and base not in ("deploy",):
        third = base[:-1] + "ies"
    elif base.endswith(("s", "x", "ch", "sh", "z")):
        third = base + "es"
    else:
        third = base + "s"
    return {base, third, VERB_PAST[base]}


VERB_LOOKUP = {}
for _base in VERB_PAST:
    for _form in _verb_forms(_base):
        VERB_LOOKUP.setdefault(_form, VERB_PAST[_base])

MID_CLAUSE_LOOKUP = {}
for _base in MID_CLAUSE_VERBS:
    for _form in _verb_forms(_base):
        MID_CLAUSE_LOOKUP[_form] = VERB_PAST[_base]

# Themes used ONLY to group commits that have no "Area:" prefix. They carry
# a label, never a canned sentence. Matching is word-boundary regex, and the
# first matching theme wins, so order specific themes first.
GROUP_THEMES = [
    ("version pins", [r"\bbump(s|ed)?\b", r"\bpin(s|ned)?\b", r"\bunpin(s|ned)?\b"]),
    ("EWTS logging", [r"\bewts\b", r"\bnwm-ewts\b", r"\blogg(ing|er)\b"]),
    ("state serialization and restart", [r"\b(de)?serializ\w*", r"\breset_time\b",
                                         r"\bwarm start\b", r"\bstate (save|saving|restore|restoration)\b"]),
    ("hindcasting", [r"\bhindcast\w*"]),
    ("verification", [r"\bverification\b", r"\bmetrics?\b", r"\bobservations?\b",
                      r"\busgs\b", r"\btxdot\b", r"\bplots?\b", r"\bplotting\b"]),
    ("forcing", [r"\bforcings?\b", r"\baorc\b", r"\bhrrr\b", r"\bgfs\b", r"\bnbm\b",
                 r"\brap\b", r"\blagged ensemble\b", r"\bshort range\b", r"\bmedium range\b"]),
    ("hydrofabric", [r"\bnhf\b", r"\bhydrofabric\b", r"\bhyfab\b", r"\bgpkg\b",
                     r"\bgeopackages?\b", r"\bvpus?\b", r"\boconus\b", r"\bcrosswalks?\b"]),
    ("BMI interfaces", [r"\bbmi\w*"]),
    ("hydrologic models", [r"\bcfe\b", r"\bsac-?sma\b", r"\bsnow-?17\b", r"\bnoah-?owp\b",
                           r"\bsft\b", r"\bsmp\b", r"\bgiuh\b", r"\blstm\b", r"\bt-?route\b"]),
    ("geospatial handling", [r"\bregrid\w*", r"\bcrs\b", r"\bgeogrid\b", r"\bmesh\b",
                             r"\bgages?\b", r"\bgeometa\b"]),
    ("configuration", [r"\bconfig\w*", r"\brealizations?\b", r"\byaml\b", r"\btemplates?\b"]),
    ("data access", [r"\bcach(e|ed|ing)\b", r"\bnetcdf\w*", r"\bxarray\b", r"\bdatasets?\b", r"\bs3\b"]),
    ("CI/CD", [r"\bci\b", r"\bci/cd\b", r"\bcicd\b", r"\bpipelines?\b", r"\bgithub actions?\b",
               r"\bworkflows?\b", r"\btrivy\b", r"\bgha\b"]),
    ("containers and builds", [r"\bdocker\w*", r"\bsifs?\b", r"\bsingularity\b", r"\bapptainer\b",
                               r"\bimages?\b", r"\bcontainers?\b", r"\bpyproject\b",
                               r"\bdependenc(y|ies)\b", r"\bcmake\w*"]),
    ("operations tooling", [r"\bslurm\b", r"\becs\b", r"\bops\b", r"\bmakefile\b", r"\bbootstrap\b"]),
    ("infrastructure", [r"\bterraform\b", r"\baws\b", r"\bamis?\b", r"\bwaf\b", r"\biam\b", r"\bvpc\b"]),
    ("testing", [r"\btests?\b", r"\btesting\b", r"\bpytest\b", r"\bunit ?tests?\b",
                 r"\bfixtures?\b", r"\bconftest\b", r"\bexpected results\b"]),
    ("documentation", [r"\breadme\b", r"\bdocs?\b", r"\bdocumentation\b", r"\blicense\b",
                       r"\bchangelog\b"]),
    ("code cleanup", [r"\brefactor\w*", r"\bclean ?up\b", r"\brenam\w+", r"\bsimplif\w+",
                      r"\btype hints?\b", r"\bunused\b"]),
]

# Map the first word of an "Area:" prefix to a group key, so
# "Ops Scripts:", "Ops Helpers:", and "Operations Enhancements:" merge.
PREFIX_ALIASES = {
    "operations": "ops", "op": "ops", "operation": "ops",
    "documentation": "docs", "doc": "docs",
    "tests": "test", "testing": "test",
    "infrastructure": "infra",
    "ci/cd": "ci", "cicd": "ci",
}

PREFIX_LABELS = {
    "ops": "operations tooling",
    "docs": "documentation",
    "test": "testing",
    "infra": "infrastructure",
    "ci": "CI/CD",
}

OTHER_KEY = "__other__"
OTHER_LABEL = "other areas"

SECTION_ORDER = ["Additions", "Removals", "Changes"]

GROUP_TEMPLATES = [
    "For {label}, this delivery {clauses}.",
    "{Label} work {clauses}.",
    "In {label}, the delivery also {clauses}.",
]

MAX_CLAUSES_PER_GROUP = 5
SUMMARY_CLAUSES_PER_GROUP = 2
SUMMARY_MAX_GROUPS = 4
# Releases with this many commits or fewer are summarized clause by clause
# instead of by group.
SMALL_RELEASE_COMMITS = 6
SMALL_RELEASE_MAX_CLAUSES = 6
TAIL_MAX_CLAUSES = 3
DUPLICATE_SIMILARITY = 0.6

# Routine groups are listed after substantive work even when they have
# more commits (seven pin bumps should not lead the summary).
LOW_PRIORITY_KEYS = {"theme:version pins", "theme:documentation"}


# ---------------------------------------------------------
# Commit text cleanup
# ---------------------------------------------------------
def cleanup_commit_text(commit):
    """
    Clean a commit subject only for release-note synthesis.

    The raw Commits section does not use this function.
    """
    commit = re.sub(r"\s*\([0-9a-f]{6,40}\)$", "", commit)
    commit = re.sub(r"^\[[^\]]+\]\s*", "", commit)
    commit = re.sub(r"^[A-Z][A-Z0-9]+-\d+\s*[:\-]?\s*", "", commit)   # JIRA-style IDs
    commit = re.sub(
        r"^(feat|fix|refactor|docs|test|build|ci|perf|style|chore)(\([^)]*\))?!?:\s*",
        "",
        commit,
        flags=re.IGNORECASE
    )
    for pattern in STRIP_PHRASES:
        commit = re.sub(pattern, "", commit)
    commit = re.sub(r"\s+", " ", commit)
    return commit.strip().rstrip(".").strip()


def is_noisy_commit(commit):
    lower = commit.lower()
    return any(re.search(pattern, lower) for pattern in NOISE_PATTERNS)


def normalized_commit_lines(commits):
    lines = []

    for raw_commit in commits:
        if raw_commit in ["No commits found.", "No changes."]:
            continue

        for commit_line in str(raw_commit).splitlines():
            commit_line = cleanup_commit_text(commit_line.strip())

            if commit_line and not is_noisy_commit(commit_line):
                lines.append(commit_line)

    return lines


# ---------------------------------------------------------
# Prefix detection and grouping
# ---------------------------------------------------------
PREFIX_RE = re.compile(r"^([A-Za-z][A-Za-z0-9 /&._+-]{0,40}?)\s*:\s+(\S.*)$")


def split_prefix(text):
    """
    Return (prefix, remainder) for subjects shaped like "Area: text".
    A prefix must be 1-4 words and must not itself start with a verb
    ("Update README: ..." is a sentence, not an area).
    """
    m = PREFIX_RE.match(text)
    if not m:
        return None, text

    prefix, rest = m.group(1).strip(), m.group(2).strip()
    words = prefix.split()

    if not (1 <= len(words) <= 4):
        return None, text

    if words[0].lower() in VERB_LOOKUP:
        return None, text

    return prefix, rest


def prefix_key(prefix):
    first = prefix.split()[0].lower()
    return "prefix:" + PREFIX_ALIASES.get(first, first)


def theme_for(text):
    lower = text.lower()
    for label, patterns in GROUP_THEMES:
        if any(re.search(p, lower) for p in patterns):
            return label
    return None


def _prose_case(label):
    """Lowercase ordinary Title-case words; keep acronyms like EA, NHF, SIFs."""
    out = []
    for word in label.split():
        if word.isalpha() and word[:1].isupper() and word[1:].islower():
            out.append(word.lower())
        else:
            out.append(word)
    return " ".join(out)


# ---------------------------------------------------------
# Clause construction
# ---------------------------------------------------------
def _convert_mid_clause_verbs(text):
    def repl(m):
        word = m.group(2)
        past = MID_CLAUSE_LOOKUP.get(word.lower())
        return m.group(1) + (past if past else word)

    return re.sub(r"(,\s*(?:and\s+)?|\s+and\s+)([A-Za-z]+)\b", repl, text)


def _lower_first_word(text):
    if not text:
        return text
    words = text.split(" ", 2)
    first = words[0]
    # Keep multi-word proper names such as "Message Pack" intact.
    if len(words) > 1 and words[1][:1].isupper():
        return text
    if first[:1].isupper() and first[1:].islower():
        return first.lower() + text[len(first):]
    return text


def to_clause(text):
    """
    Turn one commit subject (or sub-item) into a past-tense clause.
    Returns None if nothing usable remains.
    """
    text = text.strip().rstrip(".;,").strip()
    if not text:
        return None

    # "update to support X" -> "added support for X"
    m = re.match(r"^(?:update[sd]?|change[sd]?)\s+to\s+support\s+(.+)$", text, re.IGNORECASE)
    if m:
        return "added support for " + _convert_mid_clause_verbs(m.group(1))

    # "bug fix(es) for X" -> "fixed bugs in X"
    m = re.match(r"^bug ?fix(es)?\b\s*(?:for|in|to)?\s*(.*)$", text, re.IGNORECASE)
    if m:
        rest = m.group(2).strip()
        return "fixed bugs in " + rest if rest else "fixed bugs"

    # "updates to X" / "fixes for X" / "improvements to X" -> "updated X" ...
    m = re.match(r"^(updates|changes|fixes|improvements|enhancements)\s+(?:to|for|in|on)\s+(.+)$",
                 text, re.IGNORECASE)
    if m:
        verb = {"update": "updated", "updates": "updated", "changes": "changed",
                "fixes": "fixed", "improvements": "improved",
                "enhancements": "enhanced"}[m.group(1).lower()]
        return _convert_mid_clause_verbs(f"{verb} {m.group(2)}")

    words = text.split(" ", 1)
    first = words[0].lower()
    rest = words[1] if len(words) > 1 else ""

    if first == "clean" and rest.lower().startswith("up"):
        return _convert_mid_clause_verbs("cleaned " + rest)

    if first in VERB_LOOKUP:
        clause = VERB_LOOKUP[first] + (" " + rest if rest else "")
        return _convert_mid_clause_verbs(clause)

    # Noun phrases.
    # "minor updates after X" -> "made minor updates after X"
    if re.match(r"^(minor|small|various|misc\w*|general|additional)\b", text, re.IGNORECASE):
        return "made " + _convert_mid_clause_verbs(_lower_first_word(text))

    # "X note" -> "added a note on X"
    m = re.match(r"^(.+?)\s+(note|notes)$", text, re.IGNORECASE)
    if m:
        return "added a note on " + _lower_first_word(m.group(1).strip())

    # "X Updates ..." / "X fixes ..." -> "updated X ..." / "fixed X ..."
    m = re.match(r"^(.+?)\s+(updates?|changes|fixes|improvements|enhancements|cleanup)\b\s*(.*)$",
                 text, re.IGNORECASE)
    if m:
        verb = {
            "update": "updated", "updates": "updated", "changes": "changed",
            "fixes": "fixed", "improvements": "improved",
            "enhancements": "enhanced", "cleanup": "cleaned up",
        }[m.group(2).lower()]
        subject = _lower_first_word(m.group(1).strip())
        tail = (" " + m.group(3).strip()) if m.group(3).strip() else ""
        return _convert_mid_clause_verbs(f"{verb} {subject}{tail}")

    return "included " + _convert_mid_clause_verbs(_lower_first_word(text))


def commit_clauses(text):
    """
    Return the clause(s) for one commit subject.

    Subjects with a summary head followed by " - item - item" use the head
    when it is a sentence, otherwise the individual items.
    """
    parts = [p.strip() for p in re.split(r"\s+-\s+", text) if p.strip()]
    head, subs = parts[0], parts[1:]

    head_is_verb = head.split(" ", 1)[0].lower() in VERB_LOOKUP

    pieces = subs if (subs and not head_is_verb) else [head]

    clauses = []
    for piece in pieces:
        # "updated X, added Y" -> two clauses
        verb_alt = "|".join(sorted((re.escape(v) for v in VERB_LOOKUP), key=len, reverse=True))
        for part in re.split(rf",\s+(?=(?:{verb_alt})\b)", piece, flags=re.IGNORECASE):
            clauses.append(to_clause(part))

    return [c for c in clauses if c]


def clause_verb(clause):
    if clause.startswith("added support for"):
        return "added"
    return clause.split(" ", 1)[0]


def section_for_clause(clause):
    verb = clause_verb(clause)
    if verb in ADDITION_VERBS:
        return "Additions"
    if verb in REMOVAL_VERBS:
        return "Removals"
    return "Changes"


STOP_WORDS = {"the", "a", "an", "to", "of", "for", "and", "in", "on", "with", "from",
              "per", "at", "by", "latest", "most", "recent"}


def _token_set(clause):
    tokens = re.findall(r"[a-z0-9_.-]+", clause.lower())
    out = set()
    for i, t in enumerate(tokens):
        if i == 0 and t in VERB_LOOKUP.values():
            continue
        if t in STOP_WORDS:
            continue
        if len(t) > 3 and t.endswith("s") and not t.endswith("ss"):
            t = t[:-1]
        out.add(t)
    return out


def _is_near_duplicate(clause, kept):
    tokens = _token_set(clause)
    if not tokens:
        return True
    for other in kept:
        other_tokens = _token_set(other)
        union = tokens | other_tokens
        if union and len(tokens & other_tokens) / len(union) >= DUPLICATE_SIMILARITY:
            return True
    return False


def dedupe_clauses(clauses):
    kept, dropped = [], 0
    for clause in clauses:
        if _is_near_duplicate(clause, kept):
            dropped += 1
        else:
            kept.append(clause)
    return kept, dropped


def join_clauses(clauses):
    """
    Join past-tense clauses as prose. A clause that repeats the previous
    clause's leading verb drops it ("added X, Y, and Z"). Semicolons are
    used when any clause already contains a comma.
    """
    rendered = []
    prev_verb = None
    prev_had_preposition = False
    for clause in clauses:
        verb = clause.split(" ", 1)[0]
        remainder = clause.split(" ", 1)[1] if " " in clause else ""
        starts_with_preposition = re.match(r"^(to|for|in|on|with|from|by|at)\b", remainder)
        if (verb == prev_verb and remainder and not starts_with_preposition
                and not prev_had_preposition
                and not clause.startswith("added support for")):
            rendered.append(remainder)
        else:
            rendered.append(clause)
        prev_verb = verb
        prev_had_preposition = bool(starts_with_preposition)

    sep = "; " if any("," in c for c in rendered) else ", "

    if len(rendered) == 1:
        return rendered[0]
    if len(rendered) == 2:
        if sep == "; ":
            joiner = "; and "
        elif any(" and " in c for c in rendered):
            joiner = ", and "
        else:
            joiner = " and "
        return rendered[0] + joiner + rendered[1]
    return sep.join(rendered[:-1]) + sep + "and " + rendered[-1]


# ---------------------------------------------------------
# Group model
# ---------------------------------------------------------
def build_groups(commits):
    """
    Return an OrderedDict of group_key -> {
        "label": str, "commits": int,
        "clauses": [(section, clause), ...]   # in commit order
    }
    """
    groups = OrderedDict()
    prefix_originals = {}

    for text in normalized_commit_lines(commits):
        prefix, rest = split_prefix(text)

        if prefix:
            key = prefix_key(prefix)
            prefix_originals.setdefault(key, []).append(prefix)
            body = rest
        else:
            label = theme_for(text)
            key = "theme:" + label if label else OTHER_KEY
            body = text

        group = groups.setdefault(key, {"label": None, "commits": 0, "clauses": []})
        group["commits"] += 1

        for clause in commit_clauses(body):
            group["clauses"].append((section_for_clause(clause), clause))

    for key, group in groups.items():
        if key == OTHER_KEY:
            group["label"] = OTHER_LABEL
        elif key.startswith("theme:"):
            group["label"] = key[len("theme:"):]
        else:
            short = key[len("prefix:"):]
            originals = prefix_originals[key]
            if short in PREFIX_LABELS:
                group["label"] = PREFIX_LABELS[short]
            elif len(set(o.lower() for o in originals)) == 1:
                group["label"] = _prose_case(originals[0])
            else:
                group["label"] = _prose_case(originals[0].split()[0])

    # Largest groups first; "other" always last.
    ordered = sorted(
        groups.items(),
        key=lambda kv: (kv[0] == OTHER_KEY, kv[0] in LOW_PRIORITY_KEYS, -kv[1]["commits"])
    )
    return OrderedDict(ordered)


def group_sentence(label, clauses, template_index, max_clauses, is_other=False, brief=False,
                   first_in_paragraph=False):
    kept, similar = dedupe_clauses(clauses)
    other = max(0, len(kept) - max_clauses)
    kept = kept[:max_clauses]

    if not kept:
        return None

    body = join_clauses(kept)
    if brief:
        if similar or other:
            body += ", among other updates"
    elif similar and other:
        body += ", along with similar and related updates"
    elif similar:
        body += ", along with similar updates"
    elif other:
        body += ", along with related updates"

    if is_other:
        return f"This delivery {body}." if first_in_paragraph else f"This delivery also {body}."

    template = GROUP_TEMPLATES[template_index % len(GROUP_TEMPLATES)]
    return template.format(
        label=label,
        Label=label[:1].upper() + label[1:],
        clauses=body,
    )


def _oxford(items):
    if len(items) == 1:
        return items[0]
    if len(items) == 2:
        return f"{items[0]} and {items[1]}"
    return ", ".join(items[:-1]) + f", and {items[-1]}"


# ---------------------------------------------------------
# Summary paragraph
# ---------------------------------------------------------
def generate_release_summary(commits):
    """
    One prose paragraph built from the largest commit groups.
    """
    if commits in (["No commits found."], ["No changes."]):
        return commits[0]

    groups = build_groups(commits)
    if not groups:
        return "This delivery contains only merge, formatting, and similar housekeeping commits."

    named = [(k, g) for k, g in groups.items() if k != OTHER_KEY]

    # Feature groups backed by at least two commits (or the single largest
    # group when nothing has two); everything else is mentioned by name only.
    featured = [(k, g) for k, g in named if g["commits"] >= 2]
    if not featured and named:
        featured = named[:1]
    top = featured[:SUMMARY_MAX_GROUPS]
    top_keys = {k for k, _ in top}
    rest = [(k, g) for k, g in named if k not in top_keys]

    section_rank = {name: i for i, name in enumerate(SECTION_ORDER)}

    def ordered_clauses(group_list):
        # Lead with additions; they are usually the most notable work.
        pairs = [sc for _, g in group_list for sc in g["clauses"]]
        pairs.sort(key=lambda sc: section_rank[sc[0]])
        return [c for _, c in pairs]

    total = sum(g["commits"] for g in groups.values())

    # Small release: describe the commits directly, whatever their groups.
    if total <= SMALL_RELEASE_COMMITS:
        clauses, _ = dedupe_clauses(ordered_clauses(list(groups.items())))
        extra = len(clauses) > SMALL_RELEASE_MAX_CLAUSES
        body = join_clauses(clauses[:SMALL_RELEASE_MAX_CLAUSES])
        if extra:
            body += ", among other updates"
        return f"This delivery {body}."

    sentences = []

    if len(top) >= 2:
        focus = _oxford([g["label"] for _, g in top[:3]])
        sentences.append(f"Most of the work in this delivery is in {focus}.")

    for i, (key, group) in enumerate(top):
        clauses = ordered_clauses([(key, group)])
        s = group_sentence(group["label"], clauses, i, SUMMARY_CLAUSES_PER_GROUP, brief=True)
        if s:
            sentences.append(s)

    # Everything outside the featured groups is described by its own
    # clauses rather than by a vague "smaller updates" label list.
    tail_groups = list(rest)
    if OTHER_KEY in groups:
        tail_groups.append((OTHER_KEY, groups[OTHER_KEY]))

    if tail_groups:
        clauses, _ = dedupe_clauses(ordered_clauses(tail_groups))
        if clauses:
            body = join_clauses(clauses[:TAIL_MAX_CLAUSES])
            if len(clauses) > TAIL_MAX_CLAUSES:
                body += ", among other updates"
            lead = "It also" if sentences else "This delivery"
            sentences.append(f"{lead} {body}.")

    return " ".join(sentences)


# ---------------------------------------------------------
# Additions / Removals / Changes paragraphs
# ---------------------------------------------------------
def generate_pr_sections(commits):
    """
    Return {section: paragraph} with one sentence per group that has
    clauses in that section. Sections with no supporting commits are omitted.
    """
    if commits in (["No commits found."], ["No changes."]):
        return {}

    groups = build_groups(commits)
    sections = {}

    for section in SECTION_ORDER:
        sentences = []
        template_index = 0

        for key, group in groups.items():
            clauses = [c for s, c in group["clauses"] if s == section]
            if not clauses:
                continue

            sentence = group_sentence(
                group["label"], clauses, template_index, MAX_CLAUSES_PER_GROUP,
                is_other=(key == OTHER_KEY),
                first_in_paragraph=not sentences,
            )
            if sentence:
                sentences.append(sentence)
                if key != OTHER_KEY:
                    template_index += 1

        if sentences:
            sections[section] = " ".join(sentences)

    return sections


def append_release_note_section(lines, section_name, paragraph, heading_prefix="###", wrap=None):
    if not paragraph:
        return

    if heading_prefix:
        lines.append(f"{heading_prefix} {section_name}")
    else:
        lines.append(section_name)

    lines.append(textwrap.fill(paragraph, width=wrap) if wrap else paragraph)
    lines.append("")

# ------------------------------------------------------------
# Shared per-repo data collection
# ------------------------------------------------------------
def collect_repo_data(repo_info, branch):
    repo_dir = os.path.expanduser(repo_info["repo_directory"])
    prev = repo_info.get("previous_release_tag") or ""

    prev_ts, prev_iso = (None, None)
    error = None

    if prev:
        if not tag_exists(repo_dir, prev):
            error = f"Previous release tag '{prev}' not found in repository."
        else:
            prev_ts, prev_iso = get_tag_datetime(repo_dir, prev)
            if prev_ts is None:
                error = f"Unable to determine date of tag '{prev}'."

    if error:
        print(f"    ! {error}")
        commits = [f"ERROR: {error}"]
        last_commit = None
    else:
        commits, last_commit = get_commit_messages(repo_dir, branch, prev, prev_ts)

    return {
        "title": repo_title(repo_dir),
        "release": repo_info.get("release", ""),
        "notes": repo_info.get("release_notes", ""),
        "prev": prev,
        "prev_iso": prev_iso,
        "branch": branch,
        "head_sha": get_branch_head_sha(repo_dir, branch),
        "commits": commits,
        "last_commit": last_commit,
        "error": error,
    }

# ------------------------------------------------------------
# Generate markdown output
# ------------------------------------------------------------
def generate_markdown(data):
    md = []
    md.append(f"## {data['title']}")
    md.append(f"- **Release Notes**: {data['notes']}")
    md.append(f"- **Release Version**: `{data['release']}`")
    md.append(f"- **Source Branch**: `{data['branch']}`")
    md.append(f"- **Release Commit SHA**: `{data['head_sha']}`")

    if data["prev"]:
        md.append(f"- **Previous Release**: `{data['prev']}`")
        md.append(f"- **Previous Release Date**: `{data['prev_iso'] or 'Unknown'}`\n")
    else:
        md.append(f"- **Previous Release**: `N/A`\n")

    commits = data["commits"]

    if data["error"]:
        md.append(f"**{commits[0]}**")
        md.append("\n")
        return "\n".join(md)

    summary = generate_release_summary(commits)

    md.append("### Summary")
    md.append(f"{summary}\n")

    last = data["last_commit"]
    md.append(f"- **Last Commit Hash**: `{last['sha'] if last else 'N/A'}`")
    md.append(f"- **Last Commit Date**: `{last['date'] if last else 'N/A'}`\n")

    for section_name, paragraph in generate_pr_sections(commits).items():
        append_release_note_section(md, section_name, paragraph, heading_prefix="###")

    md.append("### Commits")
    md.extend([f"- {c}" for c in commits])

    md.append("\n")

    return "\n".join(md)

# ------------------------------------------------------------
# Generate text output
# ------------------------------------------------------------
def generate_text(data, output_file):
    lines = []
    lines.append("\n----------------------------------------")
    lines.append(f"{data['title']}")
    lines.append("----------------------------------------")
    lines.append(f"  Release Notes: {data['notes']}")
    lines.append(f"  Release Version: {data['release']}")
    lines.append(f"  Source Branch: {data['branch']}")
    lines.append(f"  Release Commit SHA: {data['head_sha']}")

    if data["prev"]:
        lines.append(f"  Previous Tag: {data['prev']}")
        lines.append(f"  Previous Tag Date: {data['prev_iso'] or 'Unknown'}")
    else:
        lines.append(f"  Previous Tag: N/A")

    commits = data["commits"]

    if data["error"]:
        lines.append(f"\n{commits[0]}")
        lines.append("\n")
    else:
        summary = generate_release_summary(commits)

        lines.append("\nSummary")
        lines.append(f"{textwrap.fill(summary, width=80)}\n")

        last = data["last_commit"]
        lines.append(f"- Last Commit Hash: {last['sha'] if last else 'N/A'}")
        lines.append(f"- Last Commit Date: {last['date'] if last else 'N/A'}\n")

        for section_name, paragraph in generate_pr_sections(commits).items():
            append_release_note_section(lines, section_name, paragraph, heading_prefix="", wrap=80)

        lines.append("Commits")
        lines.extend([f"- {c}" for c in commits])

        lines.append("\n")

    with open(output_file, "a") as f:
        f.write("\n".join(lines))

# ---------------------------------------------------------
# Insert Markdown Table of Contents
# ---------------------------------------------------------
def insert_markdown_toc(md_file):
    with open(md_file, "r") as f:
        lines = f.readlines()

    toc_entries = []

    for line in lines:
        if line.startswith("## "):
            heading = line.strip()[3:]

            if heading.lower() == "table of contents":
                continue

            anchor = heading.lower().replace(" ", "-")
            toc_entries.append(f"- [{heading}](#{anchor})")

    new_lines = []

    for line in lines:
        if line.strip() == "<!--TOC-->":
            new_lines.append("\n".join(toc_entries) + "\n\n")
        else:
            new_lines.append(line)

    with open(md_file, "w") as f:
        f.writelines(new_lines)

# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description=(
            "Generate release notes for multiple git repositories from commits "
            "on a branch made after each repo's previous_release_tag."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

    parser.add_argument(
        "--config", "-c",
        required=True,
        help="JSON config file"
    )

    parser.add_argument(
        "--branch", "--checkout-branch",
        dest="branch",
        default="development",
        help="Branch to checkout, pull, and collect commits from"
    )

    group = parser.add_mutually_exclusive_group(required=True)

    group.add_argument("--output")
    group.add_argument("--output_md")
    group.add_argument("--output_txt")
    group.add_argument("--output_both")

    parser.add_argument(
        "--output_json",
        nargs="?",
        const="",
        default=None,
        metavar="FILE",
        help=(
            "Optional: write a copy of the config with each repo's generated "
            "summary in release_notes. Given without FILE, writes "
            "<config name>_with_notes.json. Omit to skip."
        )
    )

    args = parser.parse_args()

    md_output_file = None
    txt_output_file = None

    if args.output_both:
        md_output_file = normalize_output_filename(args.output_both, "md")
        txt_output_file = normalize_output_filename(args.output_both, "txt")
    elif args.output:
        md_output_file = normalize_output_filename(args.output, "default")
    elif args.output_md:
        md_output_file = normalize_output_filename(args.output_md, "md")
    elif args.output_txt:
        txt_output_file = normalize_output_filename(args.output_txt, "txt")
    else:
        print("Error: No output option provided.")
        sys.exit(1)

    with open(args.config) as f:
        repos = json.load(f)

    if args.output_json is None:
        json_output_file = None
    elif args.output_json:
        json_output_file = args.output_json
    else:
        config_base, _ = os.path.splitext(args.config)
        json_output_file = f"{config_base}_with_notes.json"

    # Copy of the config for the JSON output; the original entries are left
    # untouched so this run's headers still show the config's own notes.
    repos_with_notes = json.loads(json.dumps(repos))

    all_md_sections = []

    if txt_output_file:
        with open(txt_output_file, "w") as f:
            f.write(f"Release Notes ({datetime.now().strftime('%Y-%m-%d')})\n")

    for repo, repo_out in zip(repos, repos_with_notes):
        repo_dir = os.path.expanduser(repo["repo_directory"])

        skip = repo.get("skip", False)

        if skip:
            print(f"Skipping {repo_title(repo_dir)}")
            continue

        print(f"==> Processing {repo_title(repo_dir)}")

        checkout_branch(repo_dir, args.branch)

        print("    Fetching latest branches and tags...")
        run("git fetch --all --tags --prune", cwd=repo_dir, check=True)

        print(f"    Pulling latest {args.branch}...")
        run(f"git pull --ff-only origin {shlex.quote(args.branch)}", cwd=repo_dir)

        data = collect_repo_data(repo, args.branch)

        if not data["error"]:
            count = 0 if data["commits"] == ["No commits found."] else len(data["commits"])
            print(f"    {count} commit(s) on {args.branch} after {data['prev'] or 'start of history'}")
            repo_out["release_notes"] = generate_release_summary(data["commits"])

        if txt_output_file:
            generate_text(data, txt_output_file)

        if md_output_file:
            all_md_sections.append(generate_markdown(data))

    if json_output_file:
        with open(json_output_file, "w") as f:
            json.dump(repos_with_notes, f, indent=2)
            f.write("\n")

        print(f"Done — Config with release notes written to: {json_output_file}")

    if txt_output_file:
        print(f"Done — Text written to: {txt_output_file}")

    if md_output_file:
        with open(md_output_file, "w") as f:
            f.write(f"# Release Notes ({datetime.now().strftime('%Y-%m-%d')})\n\n")
            f.write("## Table of Contents\n")
            f.write("<!--TOC-->\n\n")
            f.write("\n\n".join(all_md_sections))

        insert_markdown_toc(md_output_file)

        print(f"Done — Markdown written to: {md_output_file}")

if __name__ == "__main__":
    main()
