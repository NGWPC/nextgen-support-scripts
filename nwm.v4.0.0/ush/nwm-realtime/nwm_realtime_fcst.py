import argparse
import os
import re
import shutil
import subprocess
from datetime import datetime, timedelta


class NWMRealtimeFcst:

    # Configuration names
    CONFIG_ANA = "AnA"
    CONFIG_SHORT_RANGE = "Short_Range"
    CONFIG_MEDIUM_RANGE = "Medium_Range"
    CONFIG_EXT_ANA = "Extended_AnA"

    # Domain names
    DOMAIN_CONUS = "CONUS"
    DOMAIN_HAWAII = "Hawaii"
    DOMAIN_ALASKA = "Alaska"
    DOMAIN_PUERTO_RICO = "Puerto_Rico"

    # Forecast lengths in hours; negative means backward analysis (end=T0, start=T0+length)
    _FORECAST_LENGTHS = {
        "AnA": -3,
        "Short_Range": 18,
        "Medium_Range": 240,  # 10 days
        "Extended_AnA": -28,
    }

    # CASETYPE identifiers derived from (config, domain)
    _CASE_TYPES = {
        ("AnA", "CONUS"): "CONUS_ANALYSIS_ASSIM",
        ("Short_Range", "CONUS"): "CONUS_SHORT_RANGE",
        ("Extended_AnA", "CONUS"): "CONUS_EXT_ANALYSIS_ASSIM",
    }

    def __init__(self, config_name: str, domain: str, t0: datetime,
                 package_dir: str, working_dir: str, comout: str,
                 previous_day_comout: str):
        if config_name not in self._FORECAST_LENGTHS:
            raise ValueError(f"Unknown config_name: {config_name}")
        if domain not in (self.DOMAIN_CONUS, self.DOMAIN_HAWAII,
                          self.DOMAIN_ALASKA, self.DOMAIN_PUERTO_RICO):
            raise ValueError(f"Unknown domain: {domain}")

        self.config_name = config_name
        self.domain = domain
        self.t0 = t0
        self.package_dir = package_dir
        self.working_dir = working_dir
        self.comout = comout
        self.previous_day_comout = previous_day_comout
        self.forecast_length = self._FORECAST_LENGTHS[config_name]

    # ------------------------------------------------------------------ #
    # Derived paths (mirrors $USHnwm and $PARMnwm from the ex-script)
    # ------------------------------------------------------------------ #

    @property
    def ush_dir(self) -> str:
        return os.path.join(self.package_dir, "ush")

    @property
    def parm_dir(self) -> str:
        return os.path.join(self.package_dir, "parm")

    # ------------------------------------------------------------------ #
    # Forecast window helpers
    # ------------------------------------------------------------------ #

    @property
    def start_time(self) -> datetime:
        if self.forecast_length < 0:
            return self.t0 + timedelta(hours=self.forecast_length)
        return self.t0

    @property
    def end_time(self) -> datetime:
        if self.forecast_length < 0:
            return self.t0
        return self.t0 + timedelta(hours=self.forecast_length)

    def _ana_state_save_src(self) -> str:
        """Return the source state_save path for CONUS_ANALYSIS_ASSIM.
        Uses previous_day_comout when T0 - 3h rolls back to the previous day."""
        t_prev = self.t0 - timedelta(hours=3)
        cyc = t_prev.strftime("%H")
        base_comout = self.previous_day_comout if t_prev.date() < self.t0.date() else self.comout
        case_type = self._CASE_TYPES.get((self.config_name, self.domain))
        return os.path.join(base_comout, cyc, case_type, "state_save")

    # ------------------------------------------------------------------ #
    # configureRTE  (mirrors exnwm.sh lines 39-48)
    # ------------------------------------------------------------------ #

    def configureRTE(self) -> None:
        rte_dir = os.path.join(self.ush_dir, "nwm-rte")

        shutil.copy(os.path.join(rte_dir, "config.bashrc"), self.working_dir)
        shutil.copy(os.path.join(rte_dir, "run.sh"), self.working_dir)

        config_bashrc = os.path.join(self.working_dir, "config.bashrc")
        with open(config_bashrc) as f:
            content = f.read()
        content = re.sub(
            r"^MNT__RUN_NGEN__HOST=.*$",
            f"MNT__RUN_NGEN__HOST={self.working_dir}",
            content, flags=re.MULTILINE,
        )
        content = re.sub(
            r"^MNT__MODULE_PARAM_FILES_DIR__HOST=.*$",
            f"MNT__MODULE_PARAM_FILES_DIR__HOST={self.parm_dir}",
            content, flags=re.MULTILINE,
        )
        with open(config_bashrc, "w") as f:
            f.write(content)

        run_sh = os.path.join(self.working_dir, "run.sh")
        with open(run_sh) as f:
            content = f.read()
        bin_mounted = os.path.join(rte_dir, "bin_mounted")
        content = content.replace("$(pwd)/bin_mounted", bin_mounted)
        with open(run_sh, "w") as f:
            f.write(content)

        case_type = self._CASE_TYPES.get((self.config_name, self.domain))
        if case_type == "CONUS_ANALYSIS_ASSIM":
            src_state_save = self._ana_state_save_src()
            dst_state_save = os.path.join(self.working_dir, "state_save")
            if os.path.isdir(src_state_save):
                shutil.copytree(src_state_save, dst_state_save, dirs_exist_ok=True)

    # ------------------------------------------------------------------ #
    # runRTE  (mirrors exnwm.sh lines 50-68)
    # ------------------------------------------------------------------ #

    def runRTE(self) -> subprocess.CompletedProcess:
        case_type = self._CASE_TYPES.get((self.config_name, self.domain))
        if case_type is None:
            raise NotImplementedError(
                f"runRTE not implemented for config='{self.config_name}', domain='{self.domain}'"
            )

        if case_type == "CONUS_ANALYSIS_ASSIM":
            rte_start_time = self.t0.strftime("%Y-%m-%d %H:%M:%S")
            csdt = (self.start_time - timedelta(hours=7)).strftime("%Y-%m-%d %H:%M:%S")
            src_state_save = self._ana_state_save_src()
            # Hardcoded to the container path: working_dir is mounted as /ngwpc/tmp inside the container where RTE runs
            state_save_dir = "/ngwpc/tmp/state_save"
            if os.path.isdir(src_state_save):
                print(
                    f"INFO: Warm states found: {src_state_save}; "
                    f"T0={self.t0}; CONUS_ANALYSIS_ASSIM job will use warm states.",
                    flush = True
                )
                load_state_arg = f' --load_state_from "{state_save_dir}"'
            else:
                print(
                    f"WARNING: state_save directory not found: {src_state_save}; "
                    f"T0={self.t0}; CONUS_ANALYSIS_ASSIM job will use cold start.",
                    flush = True
                )
                load_state_arg = ""
            docker_args = (
                f'-n 2 -fconfig "standard_ana" -dt "{rte_start_time}" --save_state -rname "default_ana"'
                f'{load_state_arg}'
            )
        elif case_type == "CONUS_SHORT_RANGE":
            rte_start_time = self.t0.strftime("%Y-%m-%d %H:%M:%S")
            docker_args = (
                f'-n 2 -fconfig "short_range" -dt "{rte_start_time}" -rname "default_short" -nwmout'
            )
        elif case_type == "CONUS_EXT_ANALYSIS_ASSIM":
            t0_rte = self.t0 + timedelta(hours=abs(self.forecast_length))
            ext_start = t0_rte.strftime("%Y-%m-%d") + " 16:00:00"
            docker_args = (
                f'-n 2 -fconfig "extended_ana" -dt "{ext_start}" -rname "default_extended_ana" -nwmout'
            )

        cmd = f'source run.sh && docker_run python -um "ngen_rte.run_default" {docker_args}'
        return subprocess.run(
            ["bash", "-c", cmd],
            cwd=self.working_dir,
            check=True,
        )


def main():
    parser = argparse.ArgumentParser(description="Run NWM realtime forecast")
    parser.add_argument(
        "--t0",
        required=True,
        metavar="YYYY-MM-DD HH:MM:SS",
        help="Forecast start time (T0) in UTC, e.g. '2026-05-20 12:00:00'",
    )
    parser.add_argument(
        "--package-dir",
        required=True,
        help="Path to the NWM package directory",
    )
    parser.add_argument(
        "--working-dir",
        required=True,
        help="Path to the temporary working directory",
    )
    parser.add_argument(
        "--comout",
        required=True,
        help="Path to the COMOUT directory for reading/writing NWM output",
    )
    parser.add_argument(
        "--previous-day-comout",
        required=True,
        help="Path to the previous day's COMOUT directory, used when T0 - 3h rolls back to the prior day",
    )
    args = parser.parse_args()
    t0 = datetime.strptime(args.t0, "%Y-%m-%d %H:%M:%S")
    package_dir = args.package_dir
    working_dir = args.working_dir
    os.makedirs(working_dir, exist_ok=True)

    fcst = NWMRealtimeFcst(
        config_name=NWMRealtimeFcst.CONFIG_ANA,
        domain=NWMRealtimeFcst.DOMAIN_CONUS,
        t0=t0,
        package_dir=package_dir,
        working_dir=working_dir,
        comout=args.comout,
        previous_day_comout=args.previous_day_comout,
    )

    print(f"Config   : {fcst.config_name}")
    print(f"Domain   : {fcst.domain}")
    print(f"T0       : {fcst.t0}")
    print(f"Start    : {fcst.start_time}")
    print(f"End      : {fcst.end_time}")
    print(f"Package  : {fcst.package_dir}")
    print(f"Work dir : {fcst.working_dir}")

    fcst.configureRTE()
    fcst.runRTE()


if __name__ == "__main__":
    main()
