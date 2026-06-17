"""EcflowConnection and EcflowInterface — ecflow client lifecycle and server API."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, TypeAlias

import ecflow

from ecf_task_mgr.metadata import SubtaskInfoVariableEntry

# TODO: Replace this alias with the concrete Task type once circular imports are resolved.
Task: TypeAlias = Any

_SETTINGS_FILE = (
    Path(__file__).parent.parent.parent / "settings" / "ecflow-settings.json"
)


class EcflowConnection:
    """Wraps ecflow.Client creation, connection, and context management.

    Reads host/port from ecflow-settings.json.  Provides a context
    manager for safe handle cleanup.

    Parameters
    ----------
    settings_path : Path
        Path to JSON file with ``host`` and ``port`` keys.
    """

    def __init__(
        self,
        settings_path: Path = _SETTINGS_FILE,
    ) -> None:
        self._settings_path = settings_path
        self._host: str
        self._port: int
        self._client: ecflow.Client | None = None

        settings = self._load_settings()
        # e.g. "localhost"
        self._host = settings["host"]
        # e.g. 3141
        self._port = settings["port"]

    def _load_settings(self) -> dict[str, Any]:
        """Read and parse the settings JSON file."""
        text = self._settings_path.read_text()
        return json.loads(text)

    @property
    def host(self) -> str:
        """Server hostname."""
        return self._host

    @property
    def port(self) -> int:
        """Server port."""
        return self._port

    def connect(self) -> ecflow.Client:
        """Create ecflow.Client, do a test ping, and set as self._client."""
        raise NotImplementedError

    def disconnect(self) -> None:
        """Called on context manager exit."""
        raise NotImplementedError

    def __enter__(self) -> EcflowConnection:
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.disconnect()

    @property
    def client(self) -> ecflow.Client | None:
        return self._client


class EcflowInterface:
    """Variable and child-command operations delegated from Task/Subtask.

    Both classes delegate all ecflow server interactions here rather than
    calling ecflow.Client directly.

    ecflow has no native subtask concept — status is officially tracked only at the Task level.

    To represent state per subtask and track metadata per subtask, each ``Subtask`` instance
    is represented by a pair of ecflow variables attached to its parent task node:

    "status" variable, with key built like ``{base_key}_status`` —
        a single string value reflecting the current ``ecflow.State`` of the subtask.
    "info" variable, with key built like ``{base_key}_info`` —
        a JSON-encoded list of dicts, one entry appended per lifecycle event

    Common parameters
    -----------------
    task_path : str
        Full ecflow task path,
        e.g. ``"/nwm/hourly/jnwm_conus_analysis_assim"``.
    ecf_var_name : str
        Name of an ecflow Task variable, e.g. ``"subtask_01_status"``.
    ecf_var_subtask_base : str
        Shared base key to be used to construct a Subtask status variable and a Subtask info variable.
    ecf_pass : str
        See ecflow docs. Job password.
    ecf_rid : str
        See ecflow docs.
    """

    def __init__(self, connection: EcflowConnection) -> None:
        self._connection = connection

    @property
    def connection(self) -> EcflowConnection:
        return self._connection

    def ecf_var_exists(self, task_path: str, ecf_var_name: str) -> bool:
        """Return ``True`` if ``ecf_var_name`` exists on the task node."""
        raise NotImplementedError

    def ecf_var_create(
        self, task_path: str, ecf_var_name: str, value: str = ""
    ) -> None:
        """Add a new variable to a task node on the server."""
        raise NotImplementedError
        if not self.ecf_var_exists(task_path, ecf_var_name):
            raise RuntimeError(
                f"Variable '{ecf_var_name}' was not found on '{task_path}' after creation."
            )

    def ecf_var_set(
        self, task_path: str, ecf_var_name: str, value: str
    ) -> None:
        """Set (or overwrite) the value of an existing variable on the server."""
        raise NotImplementedError
        if not self.ecf_var_exists(task_path, ecf_var_name):
            raise RuntimeError(
                f"Variable '{ecf_var_name}' does not exist on '{task_path}'."
            )

    def ecf_var_fetch(self, task_path: str, ecf_var_name: str) -> str:
        """Get the current value of a variable from the server (return empty string if unset)."""
        raise NotImplementedError

    ### Child commands (used by Task)

    def update_task_status(
        self,
        task: Task,
        reason: str = "",
    ) -> None:
        """Send a child command to the ecflow server.

        Reads ``task._status`` to determine which child command to issue.
        Uses ``task._ecf_task_path``, ``task._ecf_pass``, ``task._ecf_rid``, and
        ``task._ecf_tryno`` to authenticate.

        ``reason`` is only used when aborting.
        """
        raise NotImplementedError

    ### Subtask variable operations (e.g. for setting "status" variable and appending to "info" variable)

    def subtask_ecf_var_pair_create(
        self, task_path: str, ecf_var_subtask_base: str
    ) -> None:
        """Create the info and status ecf_vars on the server for a subtask."""
        raise NotImplementedError

    def subtask_ecf_var_status_set(
        self, task_path: str, ecf_var_subtask_base: str, status: ecflow.State
    ) -> None:
        """Overwrite the status ecf_var for a subtask. Uses ``status.name`` as the ecf_var value."""
        raise NotImplementedError

    def subtask_ecf_var_info_append(
        self,
        task_path: str,
        ecf_var_subtask_base: str,
        entry: SubtaskInfoVariableEntry,
    ) -> None:
        """Append ``entry`` to the info ecf_var's JSON list of dicts."""
        raise NotImplementedError

    def subtask_ecf_var_info_fetch(
        self, task_path: str, ecf_var_subtask_base: str
    ) -> list[dict[str, Any]]:
        """Return the parsed info ecf_var as a list of dicts (empty list if unset)."""
        raise NotImplementedError
