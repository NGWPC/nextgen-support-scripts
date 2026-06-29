"""Module-level constants for the ecf_task_mgr package."""

from enum import Enum


class ECFVariableSuffix(str, Enum):
    """Suffix appended to a subtask's base key to complete the full name of the 2 variables storing "status" and "info"."""

    INFO = "_info"
    STATUS = "_status"


class ForcingConfigName(str, Enum):
    """NWM forecast configurations.

    Values taken from NWMRealtimeFcst in .../ush/nwm-realtime/nwm_realtime_fcst.py.
    """

    ANA = "AnA"
    SHORT_RANGE = "Short_Range"
    EXTENDED_ANA = "Extended_AnA"


class AoiType(str, Enum):
    """Type of Area of Interest for a forecast (gage or VPU)"""

    GAGE = "gage"
    VPU = "vpu"


class SubtaskType(str, Enum):
    """Allowed subtask types within an ecflow Task."""

    COLD_START = "cold_start"
    WARM_START = "warm_start"
    NONE = "no_subtask_type"


class Domain(str, Enum):
    """Geographic domains supported by NWM.

    Values taken from NWMRealtimeFcst in .../ush/nwm-realtime/nwm_realtime_fcst.py.
    """

    CONUS = "CONUS"
    ALASKA = "Alaska"
    HAWAII = "Hawaii"
    PRVI = "PRVI"


class LogFileType(str, Enum):
    """Types of log files supported by NWM / ngen.
    See nwm-rte ``ngen_logs.py`` and ``ngen_async.py``."""

    MSW_MGR = "msw"
    FCST_MGR = "fcst"
    CAL_MGR = "cal"
    NGEN_RANK = "ngen_rank"
    NGEN_STDOUT_STDERR = "ngen_stdout_stderr"


class SavedStateType(str, Enum):
    """Types of saved states supported by NWM / ngen"""

    # Intended for restarts. Created at regular intervals throughout a forecast, e.g. when using nwm-rte CLI arg --checkpoint_interval.
    CHECKPOINT = "state_checkpoint"
    # Intended for Warmstarts informed by a completed Coldstart or AnA run. Created when using nwm-rte CLI arg --save_state.
    COMPLETED = "state_completed"
