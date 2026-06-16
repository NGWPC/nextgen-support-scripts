"""Metadata structures for logging, status, and other info."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

import ecflow

from ecf_task_mgr import utils


@dataclass
class RunLogEntry:
    """For logging information about a Subtask's run."""

    subtask: str
    action: str
    run_callback_name: str
    args: list
    kwargs: dict[str, Any]
    result: Any = None
    exception: str | None = None


@dataclass
class SubtaskInfoLabelEntry:
    """For sending a new entry (json dict) to the server for a Subtask's "info" label"""

    status: ecflow.State
    reason: str | None = None
    metadata: dict[str, Any] | None = None
    ts: str = field(
        init=False,
        default_factory=lambda: utils.datetime_to_str_safe(
            datetime.now(tz=timezone.utc)
        ),
    )
