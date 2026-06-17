"""Metadata structures for logging, status, and other info."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

import ecflow

from ecf_task_mgr import utils


@dataclass
class TaskPath:
    """Full ecflow task path built from its component names."""

    suite: str
    family_outer: str
    family_inner: str
    task: str

    def __post_init__(self) -> None:
        self._validate_task_path_component("suite", self.suite)
        self._validate_task_path_component("family_outer", self.family_outer)
        self._validate_task_path_component("family_inner", self.family_inner)
        self._validate_task_path_component("task", self.task)

    def _validate_task_path_component(self, field_name: str, value: str) -> None:
        if not re.fullmatch(r"[a-z0-9_-]+", value):
            raise ValueError(f"{field_name} must match [a-z0-9_-]+, got: {value}")

    def __str__(self) -> str:
        return f"/{self.suite}/{self.family_outer}/{self.family_inner}/{self.task}"

    def __repr__(self) -> str:
        return str(self)


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
class SubtaskInfoVariableEntry:
    """For sending a new entry (json dict) to the server for a Subtask's "info" variable"""

    status: ecflow.State
    reason: str | None = None
    metadata: dict[str, Any] | None = None
    ts: str = field(
        init=False,
        default_factory=lambda: utils.datetime_to_str_safe(
            datetime.now(tz=timezone.utc)
        ),
    )
