import argparse
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta

from pathlib import Path


def touch_file_if_not_exists(file_path: str) -> None:
    """
    Create a file if it does not already exist.

    Args:
        file_path (str): Path to the file to create.
    """
    try:
        path = Path(file_path)
        if not path.exists():
            # Create the file without overwriting existing ones
            path.touch(exist_ok=False)
            print(f"File '{file_path}' created successfully.")
        else:
            print(f"File '{file_path}' already exists.")
    except PermissionError:
        print(f"Permission denied: Cannot create '{file_path}'.")
    except FileNotFoundError:
        print(f"Invalid path: Directory for '{file_path}' does not exist.")
    except OSError as e:
        print(f"OS error while creating '{file_path}': {e}")


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
                 previous_day_comout: str, vpu: str | None = None,
                 hydrofab_file: str | None = None,
                 form_assign_file: str | None = None,
                 cat_grp_file: str | None = None):
        if config_name not in self._FORECAST_LENGTHS:
            raise ValueError(f"Unknown config_name: {config_name}")
        if domain not in (self.DOMAIN_CONUS, self.DOMAIN_HAWAII,
                          self.DOMAIN_ALASKA, self.DOMAIN_PUERTO_RICO):
            raise ValueError(f"Unknown domain: {domain}")
        if form_assign_file is None:
            raise ValueError("form_assign_file is required for regionalization runs.")
        if cat_grp_file is None:
            raise ValueError("cat_grp_file is required for regionalization runs.")

        self.config_name = config_name
        self.domain = domain
        self.t0 = t0
        self.package_dir = package_dir
        self.working_dir = working_dir
        self.comout = comout
        self.previous_day_comout = previous_day_comout
        self.forecast_length = self._FORECAST_LENGTHS[config_name]
        self.vpu = vpu
        self.hydrofab_file = hydrofab_file
        self.form_assign_file = form_assign_file
        self.cat_grp_file = cat_grp_file
        self.gageid = "01123000"
    # ------------------------------------------------------------------ #
    # Derived paths (mirrors $USHnwm and $PARMnwm from the ex-script)
    # ------------------------------------------------------------------ #

    @property
    def ush_dir(self) -> str:
        return os.path.join(self.package_dir, "ush")

    @property
    def parm_dir(self) -> str:
        return os.path.join(self.package_dir, "parm")

    @property
    def hydrofab_arg(self) -> str:
        """`--hydrofab_file` option (with leading space) pointing at the gage's
        hydrofabric gpkg."""
        if not self.hydrofab_file:
            return ""
        return f' --hydrofab_file "{self.hydrofab_file}'

    @property
    def output_format_arg(self) -> str:
        return ' --output_format NetCDF'

    @property
    def form_assign_arg(self) -> str:
        return f' -faf "{self.form_assign_file}"'

    @property
    def cat_grp_arg(self) -> str:
        return f' -cgf "{self.cat_grp_file}"'

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

    # ------------------------------------------------------------------ #
    # VPU region/run_id helper
    # ------------------------------------------------------------------ #

    @property
    def vpu_arg(self) -> str:
        return f' --vpu {self.vpu}' if self.vpu else ""

    @property
    def run_id(self) -> str:
        """Unique identifier for run - VPU or gage ID"""
        return self.vpu if self.vpu else self.gageid

    def _ana_state_save_src(self) -> str:
        """Return the source state_save path for CONUS_ANALYSIS_ASSIM warm start.
        The AnA cycle runs hourly; warm states come from the previous cycle (T0-1h).
        The state_save timestamp is the analysis window start time (self.start_time = T0-3h).
        Uses previous_day_comout when T0-1h rolls back to the previous day.
        When the analysis window start time (T0-3h) is 16z, prefers the Extended AnA
        state_save from that cycle; falls back to the AnA state_save with a warning
        if that directory is not found."""
        t_cyc = self.t0 - timedelta(hours=1)
        cyc = t_cyc.strftime("%H")
        ts = self.start_time.strftime("%Y%m%d%H")
        base_comout = self.previous_day_comout if t_cyc.date() < self.t0.date() else self.comout
        ana_dir = f"CONUS_ANALYSIS_ASSIM_VPU_{self.vpu}" if self.vpu else "CONUS_ANALYSIS_ASSIM"
        ext_ana_dir = f"CONUS_EXT_ANALYSIS_ASSIM_VPU_{self.vpu}" if self.vpu else "CONUS_EXT_ANALYSIS_ASSIM"
        default_path = os.path.join(base_comout, cyc, ana_dir, f"state_save_{ts}")

        if cyc == "16":
            ext_path = os.path.join(base_comout, cyc, ext_ana_dir, f"state_save_{ts}")
            if os.path.isdir(ext_path):
                return ext_path
            print(
                f"WARNING: CONUS_EXT_ANALYSIS_ASSIM warm states are missing "
                f"(cyc={cyc}, T0={self.t0:%Y-%m-%d %H:%M:%S}); "
                f"using warm states from {ana_dir} case type instead.",
                flush=True,
            )

        return default_path

    def _ext_ana_state_save_src(self) -> str:
        """Return the source state_save path for CONUS_EXT_ANALYSIS_ASSIM warm start.
        The Extended AnA window starts at T0 - 28h (previous day 12z), so the warm
        state is the timestamped state_save valid at that start time
        (state_save_<start %Y%m%d%H>) from the previous day's 12z folder. Prefers
        CONUS_EXT_ANALYSIS_ASSIM; falls back to CONUS_ANALYSIS_ASSIM with a warning
        if the preferred directory is not found. The caller is responsible for
        checking whether the returned path exists; if it does not, a cold start
        should be used."""
        cyc = "12"
        ts = self.start_time.strftime("%Y%m%d%H")
        ana_dir = f"CONUS_ANALYSIS_ASSIM_VPU_{self.vpu}" if self.vpu else "CONUS_ANALYSIS_ASSIM"
        ext_ana_dir = f"CONUS_EXT_ANALYSIS_ASSIM_VPU_{self.vpu}" if self.vpu else "CONUS_EXT_ANALYSIS_ASSIM"
        primary_path = os.path.join(
            self.previous_day_comout, cyc, ext_ana_dir, f"state_save_{ts}"
        )
        if os.path.isdir(primary_path):
            return primary_path
        print(
            f"WARNING: {ext_ana_dir} warm states are missing at "
            f"{self.start_time:%Y-%m-%d %H:%M:%S} (T0={self.t0:%Y-%m-%d %H:%M:%S}); "
            f"using warm states from {ana_dir} case type instead.",
            flush=True,
        )
        return os.path.join(
            self.previous_day_comout, cyc, ana_dir, f"state_save_{ts}"
        )

    def _short_range_state_save_src(self) -> str:
        """Return the source state_save path for CONUS_SHORT_RANGE warm start.
        Uses the AnA state_save valid at T0 (the second AnA run of the same cycle)
        on the current day (comout/{cyc}/CONUS_ANALYSIS_ASSIM/state_save_<T0 %Y%m%d%H>).
        The caller is responsible for checking whether the returned path exists;
        if it does not, a cold start should be used."""
        cyc = self.t0.strftime("%H")
        ts = self.t0.strftime("%Y%m%d%H")
        if self.vpu:
            return os.path.join(self.comout, cyc, f"CONUS_ANALYSIS_ASSIM_VPU_{self.vpu}", f"state_save_{ts}")
        return os.path.join(self.comout, cyc, "CONUS_ANALYSIS_ASSIM", f"state_save_{ts}")

    # ------------------------------------------------------------------ #
    # configureRTE  (mirrors exnwm.sh lines 39-48)
    # ------------------------------------------------------------------ #

    def configureRTE(self) -> None:
        rte_dir = os.path.join(self.ush_dir, "nwm-rte")

        shutil.copy(os.path.join(rte_dir, "config.bashrc"), self.working_dir)
        shutil.copy(os.path.join(rte_dir, "run.sh"), self.working_dir)

        # shutil.copytree(os.path.join(rte_dir, "logs"), os.path.join(self.working_dir, "logs"), dirs_exist_ok=True)
        os.makedirs(f"{self.working_dir}/logs", exist_ok=True)
        os.makedirs(f"{self.working_dir}/logs/rte", exist_ok=True)
        os.makedirs(f"{self.working_dir}/logs/docker", exist_ok=True)
        os.makedirs(f"{self.working_dir}/logs/ngen", exist_ok=True)

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
        content = re.sub(
            r"^REPOS_COMMON_ROOT__HOST=.*$",
            f"REPOS_COMMON_ROOT__HOST={self.package_dir}/ush",
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

        state_save_src_fns = {
            "CONUS_ANALYSIS_ASSIM": self._ana_state_save_src,
            "CONUS_EXT_ANALYSIS_ASSIM": self._ext_ana_state_save_src,
            "CONUS_SHORT_RANGE": self._short_range_state_save_src,
        }

        formulation_dirs = {
            "CONUS_ANALYSIS_ASSIM": "region_ana",
            "CONUS_EXT_ANALYSIS_ASSIM": "region_extended_ana",
            "CONUS_SHORT_RANGE": "default_short",
        }

        case_type = self._CASE_TYPES.get((self.config_name, self.domain))
        dst_state_save = os.path.join(self.working_dir, "regionalization", formulation_dirs[case_type], f"{self.run_id}_state_save")
        src_state_save = state_save_src_fns[case_type]()
        if os.path.isdir(src_state_save):
            shutil.copytree(src_state_save, dst_state_save, dirs_exist_ok=True)

    # ------------------------------------------------------------------ #
    # runRTE  (mirrors exnwm.sh lines 50-68)
    # ------------------------------------------------------------------ #

    @staticmethod
    def _lookback_minutes(window_hours: int) -> int:
        """Convert a desired simulated AnA window length (hours) into the forcing
        template `LookBack` value (minutes) expected by RTE's `--lookback` option.
        msw-mgr computes the simulated window as `LookBack/60 - 1` hours, so
        `LookBack = (window_hours + 1) * 60`."""
        return (window_hours + 1) * 60

    def _docker_run(self, docker_args: str) -> int:
        """Run a single RTE invocation inside the container; return its exit code."""
        cmd = f'source run.sh && docker_run python -um "ngen_rte.run_regionalization_standalone" {docker_args}'
        print( "docker run command: ", cmd )
        result = subprocess.run(["bash", "-c", cmd], cwd=self.working_dir)
        return result.returncode

    def _docker_move_dir(self, src: str, dst: str) -> int:
        """rename a directory; return its exit code."""
        cmd = f'source run.sh && docker_run mv {src} {dst}'
        result = subprocess.run(["bash", "-c", cmd], cwd=self.working_dir)
        return result.returncode

    def _docker_restart(self, src: str, dst: str, checkpoint_dir: str) -> int:
        """Resume a single RTE invocation from an earlier stopped point inside the container; return its exit code."""
        cmd = f'source run.sh && docker_run python -um "ngen_rte.run_restart" -src {src} -dst {dst} --checkpoint_dir {checkpoint_dir}'
        print( "docker run command: ", cmd )
        result = subprocess.run(["bash", "-c", cmd], cwd=self.working_dir)
        return result.returncode

    def _archive_run_outputs(self, run_dir: str, end_time: datetime) -> None:
        """Rename the run's Output, state_save, and logs directories to timestamped
        names (<name>_<ts>), where <ts> is the simulation end time in %Y%m%d%H format.
        Preserves each pass's results before the next pass overwrites them."""
        ts = end_time.strftime("%Y%m%d%H")
        for name in ("Output", "logs", "Input"):
            src = os.path.join(run_dir, name)
            dst = os.path.join(run_dir, f"{name}_{ts}")
            if os.path.isdir(src):
                os.rename(src, dst)
                print(f"INFO: Renamed {src} -> {dst}", flush=True)
            else:
                print(f"WARNING: Cannot rename missing directory: {src}", flush=True)

        name = "state_save"
        src = os.path.join(run_dir, name)
        dst = os.path.join(run_dir, f"{name}_{ts}")
        if os.path.isdir(src):
            shutil.copytree(src, dst, dirs_exist_ok=True)
            print(f"INFO: Archived {src} -> {dst}", flush=True)
        else:
            print(f"WARNING: Cannot archive missing directory: {src}", flush=True)

    def _run_two_pass_ana(self, case_type: str, fconfig: str, rname: str,
                          src_state_save: str, window_hours: tuple,
                          extra_args: str = "",
                          run1_checkpoint_interval: int = None) -> int:
        """Run a two-pass AnA-type analysis, splitting the analysis window into
        two consecutive chunks with a state handoff.

        window_hours = (l1, l2): simulated window length (hours) of run 1 (the
        earlier chunk) and run 2 (the later chunk, ending at T0). Run 1 covers
        [T0-(l1+l2), T0-l2] and saves its end state; run 2 covers [T0-l2, T0],
        loading run 1's saved state. The window length is controlled per run via
        the RTE `--lookback` option (minutes). Returns the exit code of the first
        failing run, or of run 2 if both ran."""
        l1, l2 = window_hours
        # Host run directory; working_dir is mounted at /ngwpc/run_ngen in the container.
        if case_type == "CONUS_ANALYSIS_ASSIM":
            formulation_dir = "region_ana"
        elif case_type == "CONUS_EXT_ANALYSIS_ASSIM":
            formulation_dir = "region_extended_ana"
        else:
            print(
                f"ERROR: {case_type} unknown."
                f"exited with return code 1",
                flush=True,
            )
            return 1
            
        run_dir = os.path.join(self.working_dir, "regionalization", formulation_dir , self.run_id)
        # Hardcoded container path where RTE writes/reads the saved model state
        # (the run directory inside the /ngwpc/run_ngen mount).
        state_save_dir = f"/ngwpc/run_ngen/regionalization/{formulation_dir}/{self.run_id}_state_save"

        # Run 1 initial states: load previous-cycle warm states if present, else cold start.
        if os.path.isdir(src_state_save):
            print(
                f"INFO: Warm states found: {src_state_save}; "
                f"T0={self.t0}; {case_type} job will use warm states.",
                flush=True,
            )
            load_state_arg = f' --load_state_from "{state_save_dir}"'
        else:
            print(
                f"WARNING: state_save directory not found: {src_state_save}; "
                f"T0={self.t0}; {case_type} job will use cold start.",
                flush=True,
            )
            load_state_arg = ""

        # Run 1: earlier chunk, ends at T0 - l2, window l1 hours; saves its end state.
        dt1 = (self.t0 - timedelta(hours=l2)).strftime("%Y-%m-%d %H:%M:%S")
        checkpoint_arg = f" --checkpoint_interval {run1_checkpoint_interval}" if run1_checkpoint_interval is not None else ""
        docker_args = (
            f'-n 2 -fconfig "{fconfig}" -dt "{dt1}" --lookback {self._lookback_minutes(l1)} '
            f'--save_state -rname "{rname}"{extra_args}{load_state_arg}{checkpoint_arg}{self.vpu_arg}{self.hydrofab_arg}{self.form_assign_arg}{self.cat_grp_arg}'
            f'{self.output_format_arg}'
        )
        rc = self._docker_run(docker_args)
        if rc is None or rc != 0:
            print(
                f"ERROR: {case_type} run 1 (T0={dt1}, lookback={l1}h) "
                f"exited with return code {rc}, re-try one more time ...",
                flush=True,
            )
            # Try again
            if case_type == "CONUS_ANALYSIS_ASSIM":
               rc = self._docker_run(docker_args)
            elif case_type == "CONUS_EXT_ANALYSIS_ASSIM":
               src_dir = f"/ngwpc/run_ngen/regionalization/{formulation_dir}/{self.run_id}"
               dst_dir = f"/ngwpc/run_ngen/regionalization/{formulation_dir}/{self.run_id}_restart"
               checkpoint_dir = os.path.join(src_dir, "checkpoint" )
               rc = self._docker_restart( src_dir, dst_dir, checkpoint_dir )    
               if rc is None or rc != 0:
                   print(
                      f"ERROR: {case_type} run 1 (T0={dt1}, lookback={l1}h) "
                      f"re-try exited with return code {rc}",
                      flush=True,
                   )
                   return rc
               rc_move = self._docker_move_dir( src_dir, f"{src_dir}_failed" )
               if rc_move != 0:
                  print(
                     f"ERROR: {case_type} run 1 (T0={dt1}, lookback={l1}h) "
                     f"renaming {src_dir} to {src_dir}_failed exited with return code {rc_move}",
                     flush=True,
                  )
                  return rc_move
               rc_move = self._docker_move_dir( dst_dir, f"{src_dir}" )
               if rc_move != 0:
                  print(
                     f"ERROR: {case_type} run 1 (T0={dt1}, lookback={l1}h) "
                     f"renaming {dst_dir} to {src_dir} exited with return code {rc_move}",
                     flush=True,
                  )
                  return rc_move

        # Preserve run 1's outputs before run 2 overwrites them (end time = T0 - l2).
        self._archive_run_outputs(run_dir, self.t0 - timedelta(hours=l2))

        # Clean up run 1 artifacts so run 2 starts with a fresh working directory.
        for f in Path(run_dir).glob("*.log"):
            f.unlink()
        for f in Path(run_dir).glob("*.json"):
            f.unlink()
        #input_dir = os.path.join(run_dir, "Input")
        #if os.path.isdir(input_dir):
        #    shutil.rmtree(input_dir)

        os.makedirs(f"{self.working_dir}/regionalization/{formulation_dir}/{self.run_id}/logs", exist_ok=True)
        touch_file_if_not_exists(f"{self.working_dir}/regionalization/{formulation_dir}/{self.run_id}/logs/msw_mgr_default.log")

        # Run 2: later chunk, ends at T0, window l2 hours; loads run 1's saved state.
        dt2 = self.t0.strftime("%Y-%m-%d %H:%M:%S")
        docker_args = (
            f'-n 2 -fconfig "{fconfig}" -dt "{dt2}" --lookback {self._lookback_minutes(l2)} '
            f'--save_state -rname "{rname}"{extra_args} --load_state_from "{state_save_dir}"{self.vpu_arg}{self.hydrofab_arg}{self.form_assign_arg}{self.cat_grp_arg}'
            f'{self.output_format_arg}'
        )
        rc = self._docker_run(docker_args)
        if rc is None or rc != 0:
            print(
                f"ERROR: {case_type} run 2 (T0={dt2}, lookback={l2}h) "
                f"exited with return code {rc}, re-try one more time ...",
                flush=True,
            )
            # Try again
            rc = self._docker_run(docker_args)
            if rc != 0:
                print(
                    f"ERROR: {case_type} run 2 (T0={dt1}, lookback={l1}h) "
                    f"re-try exited with return code {rc}",
                    flush=True,
                )
                return rc

        # Preserve run 2's outputs (end time = T0).
        self._archive_run_outputs(run_dir, self.t0)
        return rc

    def runRTE(self) -> int:
        case_type = self._CASE_TYPES.get((self.config_name, self.domain))
        if case_type is None:
            raise NotImplementedError(
                f"runRTE not implemented for config='{self.config_name}', domain='{self.domain}'"
            )

        if case_type == "CONUS_ANALYSIS_ASSIM":
            # AnA 3h window split into 1h (run 1) + 2h (run 2).
            return self._run_two_pass_ana(
                case_type=case_type,
                fconfig="standard_ana",
                rname="region_ana",
                src_state_save=self._ana_state_save_src(),
                window_hours=(1, 2),
                extra_args=" -nwmout",
            )
        elif case_type == "CONUS_EXT_ANALYSIS_ASSIM":
            # Extended AnA 28h window split into 24h (run 1) + 4h (run 2).
            return self._run_two_pass_ana(
                case_type=case_type,
                fconfig="extended_ana",
                rname="region_extended_ana",
                src_state_save=self._ext_ana_state_save_src(),
                window_hours=(24, 4),
                extra_args=" -nwmout",
                run1_checkpoint_interval=1,
            )
        elif case_type == "CONUS_SHORT_RANGE":
            rte_start_time = self.t0.strftime("%Y-%m-%d %H:%M:%S")
            src_state_save = self._short_range_state_save_src()
            # Hardcoded container path where RTE writes/reads the saved model state
            # (the run directory inside the /ngwpc/run_ngen mount).
            state_save_dir = f"/ngwpc/run_ngen/regionalization/default_short/{self.run_id}_state_save"
            if os.path.isdir(src_state_save):
                print(
                    f"INFO: Warm states found at {src_state_save}; "
                    f"T0={self.t0:%Y-%m-%d %H:%M:%S}; CONUS_SHORT_RANGE job will use warm states.",
                    flush=True,
                )
                load_state_arg = f' --load_state_from "{state_save_dir}"'
            else:
                print(
                    f"WARNING: Warm states could not be found at {src_state_save}; "
                    f"T0={self.t0:%Y-%m-%d %H:%M:%S}; CONUS_SHORT_RANGE job cold started.",
                    flush=True,
                )
                load_state_arg = ""
            docker_args = (
                f'-n 2 -fconfig "short_range" -dt "{rte_start_time}" -rname "default_short" -nwmout'
                f'{load_state_arg}{self.vpu_arg}{self.hydrofab_arg}{self.form_assign_arg}{self.cat_grp_arg}{self.output_format_arg} --checkpoint_interval 1'
                f'{self.output_format_arg}'
            )
            rc = self._docker_run(docker_args)
            if rc is None or rc != 0:
               print(
                  f"ERROR: {case_type} (T0={self.t0} "
                  f"exited with return code {rc}, re-try one more time ...",
                  flush=True,
               )
               #backup the failed run, this is the directory in the container
               src_dir = os.path.join("/ngwpc/run_ngen/regionalization/default_short", f"{self.run_id}_failed")
               dst_dir = os.path.join("/ngwpc/run_ngen/regionalization/default_short", self.run_id)
               rc_move = self._docker_move_dir( dst_dir, src_dir )
               if rc_move != 0:
                  print(
                     f"ERROR: {case_type} run 1 (T0={dt1}, lookback={l1}h) "
                     f"renaming {dst_dir} to {src_dir} exited with return code {rc_move}",
                     flush=True,
                  )
                  return rc_move
               checkpoint_dir = os.path.join(src_dir, "checkpoint" )
               return self._docker_restart( src_dir, dst_dir, checkpoint_dir )


def main():
    parser = argparse.ArgumentParser(description="Run NWM realtime forecast")
    parser.add_argument(
        "--t0",
        required=True,
        metavar="YYYY-MM-DD HH:MM:SS",
        help="Forecast start time (T0) in UTC, e.g. '2026-05-20 12:00:00'",
    )
    parser.add_argument(
        "--config-name",
        default=NWMRealtimeFcst.CONFIG_ANA,
        choices=[
            NWMRealtimeFcst.CONFIG_ANA,
            NWMRealtimeFcst.CONFIG_SHORT_RANGE,
            NWMRealtimeFcst.CONFIG_MEDIUM_RANGE,
            NWMRealtimeFcst.CONFIG_EXT_ANA,
        ],
        help=(
            "NWM configuration to run "
            f"(default: {NWMRealtimeFcst.CONFIG_ANA})"
        ),
    )
    parser.add_argument(
        "--domain",
        default=NWMRealtimeFcst.DOMAIN_CONUS,
        choices=[
            NWMRealtimeFcst.DOMAIN_CONUS,
            NWMRealtimeFcst.DOMAIN_HAWAII,
            NWMRealtimeFcst.DOMAIN_ALASKA,
            NWMRealtimeFcst.DOMAIN_PUERTO_RICO,
        ],
        help=(
            "NWM domain to run "
            f"(default: {NWMRealtimeFcst.DOMAIN_CONUS})"
        ),
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
    parser.add_argument(
        "--vpu",
        default=None,
        help="VPU identifier for CONUS runs, e.g. '03S'",
    )
    parser.add_argument(
        "--hydrofab_file",
        default=None,
        help="Path to the local hydrofabric geopackage file"
    )
    parser.add_argument(
        "--form-assign-file",
        required=True,
        help="Path to the regionalization formulation assignment file"
    )
    parser.add_argument(
        "--cat-grp-file",
        default=None,
        help="Path to the regionalization catchment grouping file"
    )
    args = parser.parse_args()
    t0 = datetime.strptime(args.t0, "%Y-%m-%d %H:%M:%S")
    package_dir = args.package_dir
    working_dir = args.working_dir
    os.makedirs(working_dir, exist_ok=True)

    fcst = NWMRealtimeFcst(
        config_name=args.config_name,
        domain=args.domain,
        t0=t0,
        package_dir=package_dir,
        working_dir=working_dir,
        comout=args.comout,
        previous_day_comout=args.previous_day_comout,
        vpu=args.vpu,
        hydrofab_file=args.hydrofab_file,
        form_assign_file=args.form_assign_file,
        cat_grp_file=args.cat_grp_file,
    )

    print(f"Config   : {fcst.config_name}")
    print(f"Domain   : {fcst.domain}")
    print(f"T0       : {fcst.t0}")
    print(f"Start    : {fcst.start_time}")
    print(f"End      : {fcst.end_time}")
    print(f"Package  : {fcst.package_dir}")
    print(f"Work dir : {fcst.working_dir}")

    try:
        fcst.configureRTE()
    except Exception as e:
        print(f"ERROR: configureRTE failed: {e}", flush=True)
        sys.exit(1)

    rc = fcst.runRTE()
    if rc != 0:
        print(f"ERROR: runRTE exited with return code {rc}", flush=True)
        sys.exit(rc)


if __name__ == "__main__":
    main()
