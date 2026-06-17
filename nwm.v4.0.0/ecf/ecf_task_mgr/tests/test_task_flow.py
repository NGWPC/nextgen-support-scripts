"""End-to-end flow: construct all public classes and run a subtask through Task.run_subtask."""

import logging
import socket
import time
from datetime import datetime, timezone

import ecflow
import pytest

from ecf_task_mgr.constants import AoiType, SubtaskType
from ecf_task_mgr.ecf_interface import EcflowConnection, EcflowInterface
from ecf_task_mgr.metadata import TaskPath
from ecf_task_mgr.tasks import Task

TEST_TASK_PATH = TaskPath(
    suite="nwm",
    family_outer="hourly",
    family_inner="nwm_analysis_assim",
    task="jnwm_conus_analysis_assim",
)


def sample_run_callback(arg1: str, arg2: str, *, kwarg1: str, kwarg2: str) -> str:
    """A sample / mock callback for testing Subtask behavior."""
    logging.info("Inside subtask sample callback, starting...")
    time.sleep(0.2)
    logging.info("Inside subtask sample callback...")
    time.sleep(0.2)
    logging.info("Inside subtask sample callback, ending...")
    return "_".join([arg1, arg2, kwarg1, kwarg2])


@pytest.fixture()
def stub_settings(tmp_path):
    """Write a minimal ecflow-settings.json into a temp directory."""
    settings = tmp_path / "ecflow-settings.json"
    settings.write_text('{"host": "localhost", "port": 3141}')
    return settings


@pytest.fixture()
def connection(stub_settings):
    return EcflowConnection(settings_path=stub_settings)


@pytest.fixture()
def interface(connection):
    return EcflowInterface(connection=connection)


@pytest.fixture()
def task(connection):
    return Task(
        connection=connection,
        ecf_task_path=TEST_TASK_PATH,
        ecf_tryno=1,
        ecf_pass="abc123",
        ecf_rid="12345",
    )


@pytest.fixture()
def subtask(task):
    return task.create_subtask(
        subtask_type=SubtaskType.NONE,
        cycle_dt=datetime(2026, 6, 15, 12, 0, 0, tzinfo=timezone.utc),
        aoi_type=AoiType.VPU,
        aoi_id="03S",
        run_callback=sample_run_callback,
        run_callback_args=["one", "two"],
        run_callback_kwargs={"kwarg1": "three", "kwarg2": "four"},
    )


class TestEcflowConnection:
    def test_connection(self):
        """Confirm a local ecflow server is reachable at localhost:3141."""
        logging.info("Testing raw socket connection to ecflow server")
        try:
            with socket.create_connection(("localhost", 3141), timeout=2):
                pass
        except OSError as exc:
            pytest.fail(f"Could not reach ecflow server at localhost:3141: {exc}")

    def test_connection_ecflow_client(self):
        """Confirm a local ecflow server responds to a Python ecflow client ping."""
        logging.info("Testing ecflow.Client connection and ping to ecflow server")
        try:
            client = ecflow.Client("localhost", 3141)
            client.ping()
        except Exception as exc:
            pytest.fail(
                f"ecflow.Client could not ping localhost:3141: {type(exc).__name__}: {exc}"
            )


class TestTaskFlow:
    def test_connection_constructed(self, connection):
        assert connection.host == "localhost"
        assert connection.port == 3141

    def test_task_constructed(self, task):
        assert (
            str(task._ecf_task_path)
            == "/nwm/hourly/nwm_analysis_assim/jnwm_conus_analysis_assim"
        )

    def test_subtask_constructed(self, subtask):
        assert subtask.identity_string.endswith("__03S")

    def test_subtask_run_noop(self, task, subtask):
        result = task.run_subtask(subtask, verbosity=1)
        assert result == "one_two_three_four"

    def test_subtask_run_noop_with_return_value(self, task):
        st = task.create_subtask(
            subtask_type=SubtaskType.NONE,
            cycle_dt=datetime(2026, 6, 15, 12, 0, 0, tzinfo=timezone.utc),
            aoi_type=AoiType.GAGE,
            aoi_id="01123000",
            run_callback=sample_run_callback,
            run_callback_args=["foo", "bar"],
            run_callback_kwargs={"kwarg1": "baz", "kwarg2": "qux"},
        )
        assert task.run_subtask(st, verbosity=1) == "foo_bar_baz_qux"
