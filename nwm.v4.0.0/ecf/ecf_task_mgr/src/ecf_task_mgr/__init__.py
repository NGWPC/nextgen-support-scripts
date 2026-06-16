"""ecf_task_mgr — Python OOP interface for ecflow task/subtask management."""

from ecf_task_mgr.constants import (
    AoiType,
    Domain,
    ECFLabelSuffix,
    ForcingConfigName,
    SubtaskType,
)
from ecf_task_mgr.ecf_interface import EcflowConnection, EcflowInterface
from ecf_task_mgr.logging_setup import setup_logging
from ecf_task_mgr.tasks import Subtask, Task

setup_logging()

__all__ = [
    "AoiType",
    "EcflowConnection",
    "EcflowInterface",
    "Task",
    "Subtask",
    "SubtaskType",
    "ECFLabelSuffix",
    "ForcingConfigName",
    "Domain",
]
