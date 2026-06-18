"""EcflowConnection and EcflowInterface — ecflow client lifecycle and server API."""

from __future__ import annotations

import json
import logging
from dataclasses import asdict
from pathlib import Path
from typing import Any, TypeAlias

import ecflow

from ecf_task_mgr.metadata import SubtaskInfoVarEntry, TaskPath

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
        self._client = ecflow.Client(self._host, self._port)
        self._client.ping()
        return self._client

    def load_suite(self, suite_def_path: Path, force: bool = False) -> None:
        """Load a ECF suite definition file to the server."""
        if self._client is None:
            raise RuntimeError("ecflow client is not connected.")
        if not suite_def_path.exists():
            raise FileNotFoundError(f"Suite definition not found: {suite_def_path}")
        self._client.load(str(suite_def_path), force)

    def disconnect(self) -> None:
        """Called on context manager exit."""
        self._client = None

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

    "status" variable, with key built like ``{base_key}status`` —
        a single string value reflecting the current ``ecflow.State`` of the subtask.
    "info" variable, with key built like ``{base_key}_info`` —
        a JSON-encoded list of dicts, one entry appended per lifecycle event

    Common parameters
    -----------------
    task_path : str
        Full ecflow task path,
        e.g. ``"/nwm/hourly/jnwm_conus_analysis_assim"``.
    var_name : str
        Name of an ecflow Task variable, e.g. ``"subtask_01_status"``.
    var_subtask_base : str
        Shared base key to be used to construct a Subtask status variable and a Subtask info variable.
    ecf_pass : str
        See ecflow docs. Job password.
    ecf_rid : str
        See ecflow docs.
    """

    def __init__(self, conn: EcflowConnection) -> None:
        self._conn = conn

    @property
    def conn(self) -> EcflowConnection:
        return self._conn

    @property
    def _defs(self) -> ecflow.Defs:
        """Fresh defs from the server (sync is called each time this is accessed)."""
        if self._conn.client is None:
            raise RuntimeError("ecflow client is not connected.")
        self._conn.client.sync_local()
        defs = self._conn.client.get_defs()
        if defs is None:
            raise RuntimeError("ecflow client definitions are not available.")
        return defs

    ### TODO replace Any with Task after resolving circular imports

    def get_node(self, node: TaskPath | str | Any) -> ecflow.Node:
        """Return the ecflow.Node object for a given task path."""
        node = str(node)
        node_obj = self._defs.find_abs_node(node)
        if node_obj is None:
            raise RuntimeError(f"Node {repr(node)} not found on server.")
        return node_obj

    def var_exists(self, node: TaskPath | str | Any, var_name: str) -> bool:
        """Return ``True`` if ``var_name`` exists on the task node."""
        node_obj = self.get_node(node)
        return bool(node_obj.find_variable(var_name))

    def var_create(
        self, node: TaskPath | str | Any, var_name: str, value: str = ""
    ) -> None:
        """Add a new variable to a node (e.g. a task path) on the server."""
        node = str(node)
        logging.info(
            f"Creating variable {repr(var_name)} on {repr(node)} with initial value: {repr(value)}"
        )
        if self._conn.client is None:
            raise RuntimeError("ecflow client is not connected.")
        self._conn.client.alter(node, "add", "variable", var_name, value)

    def var_set(self, node: TaskPath | str | Any, var_name: str, value: str) -> None:
        """Set (or overwrite) the value of an existing variable on the server."""
        if not self.var_exists(node, var_name):
            raise RuntimeError(
                f"Variable {repr(var_name)} does not exist on node: {repr(node)}."
            )
        self._conn.client.alter(str(node), "change", "variable", var_name, value)

    def var_fetch(self, node: TaskPath | str | Any, var_name: str) -> str:
        """Get the current value of a variable from the server (return empty string if unset)."""
        node_obj = self.get_node(node)
        var = node_obj.find_variable(var_name)
        if var is None:
            raise RuntimeError(
                f"Variable {repr(var_name)} not found on node {repr(node)}."
            )
        return var.value()

    ### Child commands (used by Task)

    def update_task_status(
        self,
        task: Task,
        reason: str = "",
    ) -> None:
        """Send a child command to the ecflow server.

        Reads ``task.status`` to determine which child command to issue.
        Uses ``task.ecf_path``, ``task._ecf_pass``, ``task._ecf_rid``, and
        ``task._ecf_tryno`` to authenticate.

        ``reason`` is only used when aborting.
        """
        raise NotImplementedError

    ### Subtask variable operations (e.g. for setting "status" variable and appending to "info" variable)
    ### TODO replace Any with Subtask after resolving circular imports

    def subtask_var_pair_create(self, subtask: Any) -> None:
        """Create the info and status variables on the server for a subtask."""
        self.var_create(subtask.task, subtask.var_status)
        self.var_create(subtask.task, subtask.var_info)

    def subtask_var_status_set(self, subtask: Any, status: ecflow.State) -> None:
        """Overwrite a subtask's status variable on the server."""
        self.var_set(subtask.task, subtask.var_status, status.name)

    def subtask_var_info_append(self, subtask: Any, entry: SubtaskInfoVarEntry) -> None:
        """Append to a subtask's info variable on the server (this holds a JSON list of dicts)"""
        data = self.subtask_var_info_fetch(subtask)
        logging.info(
            f"Appending {asdict(entry)} to subtask info variable {subtask.var_info} for task {subtask.task} on server"
        )
        data.append(asdict(entry))
        self.var_set(subtask.task, subtask.var_info, json.dumps(data, indent=2))

    def subtask_var_info_fetch(self, subtask: Any) -> list[dict[str, Any]]:
        """Fetch the value of the subtask info variable.
        If it is non-empty, return a json-parse of it.
        Otherwise, return an empty list."""
        raw_value = self.var_fetch(subtask.task, subtask.var_info)
        if raw_value:
            data = json.loads(raw_value)
        else:
            data = []
        return data
