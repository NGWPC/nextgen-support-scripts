"""Classes to manage arbitrary ecflow tasks and subtasks for needs of NWM operational forecasts.
Tasks are defined by the ecflow framework, but subtasks are not."""

from __future__ import annotations

import hashlib
import json
import logging
from dataclasses import asdict, replace
from datetime import datetime
from typing import Any, Callable

import ecflow

from ecf_task_mgr.constants import AoiType, ECFLabelSuffix, SubtaskType
from ecf_task_mgr.ecf_interface import EcflowInterface
from ecf_task_mgr.metadata import RunLogEntry, SubtaskInfoLabelEntry
from ecf_task_mgr.utils import datetime_to_str_safe

logger = logging.getLogger("ecf_task_mgr.tasks")


class Task:
    """Owns task-level ecflow child commands (init/complete/abort) and orchestrates subtask execution."""

    def __init__(
        self,
        connection: Any,  # TODO add EcflowConnection type hint after resolving circular imports
        ecf_name: str,
        ecf_tryno: int,
        ecf_pass: str,
        ecf_rid: str,
    ) -> None:
        self._ecf_name = ecf_name
        self._ecf_tryno = ecf_tryno
        self._ecf_pass = ecf_pass
        self._ecf_rid = ecf_rid
        self._status: ecflow.State = ecflow.State.queued
        self._interface = EcflowInterface(connection)
        self._subtasks: list[Subtask] = []

    def init_task(self) -> None:
        self._status = ecflow.State.active
        self._interface.update_task_status(self)

    def complete_task(self) -> None:
        self._status = ecflow.State.complete
        self._interface.update_task_status(self)

    def abort_task(self, reason: str = "") -> None:
        self._status = ecflow.State.aborted
        self._interface.update_task_status(self, reason)

    def create_subtask(
        self,
        subtask_type: SubtaskType,
        cycle_dt: datetime,
        aoi_type: AoiType,
        aoi_id: str,
        run_callback: Callable | None = None,
        run_callback_args: list | None = None,
        run_callback_kwargs: dict | None = None,
    ) -> Subtask:
        subtask = Subtask(
            task=self,
            subtask_type=subtask_type,
            cycle_dt=cycle_dt,
            aoi_type=aoi_type,
            aoi_id=aoi_id,
            run_callback=run_callback,
            run_callback_args=run_callback_args
            if run_callback_args is not None
            else [],
            run_callback_kwargs=run_callback_kwargs
            if run_callback_kwargs is not None
            else {},
        )
        self._subtasks.append(subtask)
        return subtask

    def run_subtask(self, subtask: Subtask, verbosity: int = 1) -> Any:
        """Execute a subtask's callback and return its result."""
        if subtask.run_callback is None:
            raise RuntimeError("subtask.run_callback is not set.")
        callable_name = getattr(
            subtask.run_callback, "__name__", repr(subtask.run_callback)
        )
        run_log_entry = RunLogEntry(
            subtask=subtask.identity_string,
            action="running",
            run_callback_name=callable_name,
            args=subtask.run_callback_args,
            kwargs=subtask.run_callback_kwargs,
        )
        if verbosity >= 1:
            logger.info(json.dumps(asdict(run_log_entry)))
        result = None
        exception = None
        try:
            result = subtask.run_callback(
                *subtask.run_callback_args,
                **subtask.run_callback_kwargs,
            )
        except Exception as exc:
            exception = exc
        done_log_entry = replace(
            run_log_entry,
            action="done running",
            result=repr(result),
            exception=str(exception) if exception else None,
        )
        if verbosity >= 1:
            logger.info(json.dumps(asdict(done_log_entry)))
        if exception is not None:
            raise exception
        return result


class Subtask:
    """Subtask with generic callable and reporting abilities. Not defined by ecflow framework itself.

    Contains:
        The instance of its parent Task.
        ID information.
        A generic callable (and associated args and kwargs for the callable) to be executed.

    Can make calls to the ecflow server via its parent Task's EcflowInterface attribute,
    for reporting status and appending other info to a label.
    """

    def __init__(
        self,
        task: Task,
        ### Attributes of the subtask used for identity and server label management
        subtask_type: SubtaskType,  # Not built-in to ecflow; defined by this package.
        cycle_dt: datetime,  # Not built-in to ecflow; defined by NOAA NCO (see NCO prod_utils).
        aoi_type: AoiType,  # Not built-in to ecflow; defined by this package.
        aoi_id: str,  # Not built-in to ecflow; defined by this package.
        ### Execution
        run_callback: Callable | None = None,
        run_callback_args: list | None = None,
        run_callback_kwargs: dict | None = None,
    ) -> None:
        self._task = task
        self._subtask_type = subtask_type
        self._cycle_dt = cycle_dt
        self._aoi_type = aoi_type
        self._aoi_id = aoi_id
        self._base_key = self.identity_string
        self._status: ecflow.State = ecflow.State.queued
        self.run_callback = run_callback
        self.run_callback_args = (
            run_callback_args if run_callback_args is not None else []
        )
        self.run_callback_kwargs = (
            run_callback_kwargs if run_callback_kwargs is not None else {}
        )

    @property
    def identity_string(self) -> str:
        """String that uniquely identifies this subtask instance, used for defining ecflow labels for storing status and other information about this subtask."""
        return f"{self._task._ecf_name}__{self._subtask_type}__{datetime_to_str_safe(self._cycle_dt)}__{self._aoi_type}__{self._aoi_id}"

    @property
    def _hashed_identity_string(self) -> str:
        digest = hashlib.md5(self.identity_string.encode()).hexdigest()[:12]
        return f"{digest}"

    @property
    def status(self) -> ecflow.State:
        return self._status

    @property
    def label_status(self) -> str:
        """Full name of ecflow label name for this subtask's "status" label."""
        return f"{self._base_key}{ECFLabelSuffix.STATUS}"

    @property
    def label_info(self) -> str:
        """Full name of ecflow label name for this subtask's "info" label."""
        return f"{self._base_key}{ECFLabelSuffix.INFO}"

    def server_set_status(
        self,
        status: ecflow.State,
        reason: str = "",
        metadata: dict[str, Any] | None = None,
    ) -> None:
        """Update subtask status and append a status/info lifecycle entry on the ecflow server.
        ``reason`` is an ecflow convention intended to be used when a task is being aborted."""
        self._status = status
        interface = self._task._interface
        # if interface is not None:
        interface.subtask_label_status_set(self._task._ecf_name, self._base_key, status)
        entry = SubtaskInfoLabelEntry(
            status=status,
            reason=reason,
            metadata=metadata,
        )
        interface.subtask_label_info_append(
            self._task._ecf_name,
            self._base_key,
            entry,
        )
