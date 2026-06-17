"""Module-level constants for the ecf_task_mgr package."""

from enum import StrEnum


class ECFVariableSuffix(StrEnum):
    """Suffix appended to a subtask's base key to complete the full name of the 2 variables storing "status" and "info"."""

    INFO = "_info"
    STATUS = "_status"


class ForcingConfigName(StrEnum):
    """NWM forecast configurations.

    Values taken from NWMRealtimeFcst in .../ush/nwm-realtime/nwm_realtime_fcst.py.
    """

    ANA = "AnA"
    SHORT_RANGE = "Short_Range"
    EXTENDED_ANA = "Extended_AnA"


class AoiType(StrEnum):
    """Type of Area of Interest for a forecast (gage or VPU)"""

    GAGE = "gage"
    VPU = "vpu"


class SubtaskType(StrEnum):
    """Allowed subtask types within an ecflow Task."""

    COLD_START = "cold_start"
    WARM_START = "warm_start"
    NONE = "no_subtask_type"


class Domain(StrEnum):
    """Geographic domains supported by NWM.

    Values taken from NWMRealtimeFcst in .../ush/nwm-realtime/nwm_realtime_fcst.py.
    """

    CONUS = "CONUS"
    ALASKA = "Alaska"
    HAWAII = "Hawaii"
    PRVI = "PRVI"
