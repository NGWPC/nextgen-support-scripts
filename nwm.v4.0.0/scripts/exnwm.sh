#!/usr/bin/env bash 

#################################################################################
#  Program Name: nwm
#                                                                               #
#  Author(s)/Contact(s): RTX & OWP                                             #
#                                                                               #
#  This script will execute the analysis assim using RTE.                      #
#  The CONUS short range will regrid the RAP, HRRR, STAGE IV and MRMS data.    #
#                                                                               #
#  Input: compath.py -o {rap,hrrr,mrms}/v#.#/                                   #
#                                                                               #
#  Output: $COMOUT/analysis_assim/                                             #
#          nwm.$cycle.analysis_assim.conus.tm00.conus.nc                       #
#                                                                               #
# For non-fatal errors output is witten to $DATA                                #
# History:                                                                      #
#################################################################################
# ----------------------------------------------------------------------------- #
# Main script ----------------------------------------------

seton='-xa'
setoff='+xa'

set $setoff
echo ' '
echo '********************************************************'
echo '** National Water Model (NWM) ANALYSIS ASSIM FORCING  **'
echo '********************************************************'
echo -e "\n=====> Starting $0 at : `date`\n"
set $seton

cd $DATA

msg="Starting $USHnwm/rte-nwm at `date`"

# Scan RTE log files in ${DATA}/logs/rte/ for warnings and errors.
# Prints all WARNING/ERROR/FATAL/CRITICAL/SEVERE lines and calls err_chk
# if any error-level lines are found, or if the log dir/files are missing.
check_rte_logs() {
    set $setoff
    local log_dir="${DATA}/logs/rte"

    if [[ ! -d "${log_dir}" ]]; then
        echo "ERROR: RTE log directory not found: ${log_dir}" >&2
        export err=1; err_chk
        return
    fi

    local -a log_files=( "${log_dir}"/rte_*.log )
    if [[ ! -e "${log_files[0]}" ]]; then
        echo "ERROR: No RTE log files found in ${log_dir}" >&2
        export err=1; err_chk
        return
    fi

    local error_count=0 warning_count=0 info_count=0
    local log_file file_warnings file_errors n

    for log_file in "${log_files[@]}"; do
        n=$(grep -cE '^\S+[[:space:]]+RTE[[:space:]]+INFO[[:space:]]' \
            "${log_file}" 2>/dev/null) || true
        info_count=$(( info_count + ${n:-0} ))

        file_warnings=$(grep -E '^\S+[[:space:]]+RTE[[:space:]]+WARNING[[:space:]]' \
                        "${log_file}" 2>/dev/null) || true
        if [[ -n "${file_warnings}" ]]; then
            echo "${file_warnings}"
            n=$(grep -cE '^\S+[[:space:]]+RTE[[:space:]]+WARNING[[:space:]]' \
                "${log_file}" 2>/dev/null) || true
            warning_count=$(( warning_count + ${n:-0} ))
        fi

        file_errors=$(grep -E '^\S+[[:space:]]+RTE[[:space:]]+(ERROR|FATAL|CRITICAL|SEVERE)[[:space:]]' \
                      "${log_file}" 2>/dev/null) || true
        if [[ -n "${file_errors}" ]]; then
            echo "${file_errors}"
            n=$(grep -cE '^\S+[[:space:]]+RTE[[:space:]]+(ERROR|FATAL|CRITICAL|SEVERE)[[:space:]]' \
                "${log_file}" 2>/dev/null) || true
            error_count=$(( error_count + ${n:-0} ))
        fi
    done

    echo "RTE log scan: ${info_count} INFO message(s) found in ${log_dir}."
    if [[ ${warning_count} -gt 0 ]]; then
        echo "RTE log scan: ${warning_count} WARNING(s) found in ${log_dir}."
    fi
    if [[ ${error_count} -gt 0 ]]; then
        echo "RTE log scan: ${error_count} ERROR/FATAL/CRITICAL/SEVERE line(s) found in ${log_dir}." >&2
        export err=1; err_chk
    fi
    set $seton
}

# configure and run RTE
if [[ ${CASETYPE} == "CONUS_ANALYSIS_ASSIM" ]]; then
  python  ${USHnwm}/nwm-realtime/nwm_realtime_fcst.py    \
    --config-name "AnA"                                  \
    --domain "CONUS"                                     \
    --t0 "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00" \
    --package-dir ${HOMEnwm} \
    --working-dir ${DATA}  \
    --comout ${COMOUT}     \
    --previous-day-comout ${COMOUTm1}
elif [[ ${CASETYPE} == "CONUS_SHORT_RANGE" ]]; then
  python  ${USHnwm}/nwm-realtime/nwm_realtime_fcst.py \
    --config-name "Short_Range"                          \
    --domain "CONUS"                                     \
    --t0 "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00" \
    --package-dir ${HOMEnwm} \
    --working-dir ${DATA}  \
    --comout ${COMOUT}     \
    --previous-day-comout ${COMOUTm1}
elif [[ ${CASETYPE} == "CONUS_EXT_ANALYSIS_ASSIM" ]]; then
  export cyc=16
  python  ${USHnwm}/nwm-realtime/nwm_realtime_fcst.py \
    --config-name "Extended_AnA"                      \
    --domain "CONUS"                                  \
    --t0 "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00" \
    --package-dir ${HOMEnwm} \
    --working-dir ${DATA}  \
    --comout ${COMOUT}     \
    --previous-day-comout ${COMOUTm1}
fi


##Copy RTE config and run.sh script
#cp $USHnwm/nwm-rte/config.bashrc ./
#cp $USHnwm/nwm-rte/run.sh  ./
#
##Update RTE config for the working directory
#sed -i -e "/^MNT__RUN_NGEN__HOST=/s|.*|MNT__RUN_NGEN__HOST=${DATA}|" \
#       -e "/^MNT__MODULE_PARAM_FILES_DIR__HOST=/s|.*|MNT__MODULE_PARAM_FILES_DIR__HOST=${PARMnwm}|" \
#	./config.bashrc
##Update RTE path
#sed -i -e "s|\$(pwd)/bin_mounted|${USHnwm}/nwm-rte/bin_mounted|" ./run.sh
#
#source run.sh
#
#rte_start_time="${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00"
#outcyc=${cyc}
#
##Run RTE default configuration
#if [[ ${CASETYPE} == "CONUS_ANALYSIS_ASSIM" ]]; then
#   docker_run python -um "ngen_rte.run_default" -n 2 \
#	   -fconfig "standard_ana" -dt "$rte_start_time" -rname "default_ana"
#elif [[ ${CASETYPE} == "CONUS_SHORT_RANGE" ]]; then
#   docker_run python -um "ngen_rte.run_default"  -n 2 \
#	   -fconfig "short_range" -dt "$rte_start_time" -rname "default_short"  -nwmout
#elif [[ ${CASETYPE} == "CONUS_EXT_ANALYSIS_ASSIM" ]]; then
#   #Extended AnA cycle is 16z
#   rte_extana_start_time="${PDY:0:4}-${PDY:4:2}-${PDY:6:2} 16:00:00"
#   outcyc='16'
#   docker_run python -um "ngen_rte.run_default" -n 2 \
#   -fconfig "extended_ana" -dt "$rte_extana_start_time" -rname "default_extended_ana" -nwmout
##fi

#export err=$?
#if [ "$err" -ne 0 ]; then
#     errMsg="${jobid} failed because RTE failed."
#     err_exit "$errMsg"
#fi

check_rte_logs

if [ ! -d ${COMOUT}/${cyc}/${CASETYPE} ]; then
	mkdir -p ${COMOUT}/${cyc}/${CASETYPE}
fi

if [ ! -d ${COMOUT}/logs/${cyc}/${CASETYPE} ]; then
	mkdir -p ${COMOUT}/logs/${cyc}/${CASETYPE}
fi

#NGen logs
cp ${DATA}/default/test_bmi/*/*.log ${COMOUT}/logs/${cyc}/${CASETYPE}/

#log messages from MSWM
cp -r ${DATA}/logs/* ${COMOUT}/logs/${cyc}/${CASETYPE}/

export err=$?; err_chk


if [[ ${CASETYPE} == "CONUS_ANALYSIS_ASSIM" || ${CASETYPE} == "CONUS_EXT_ANALYSIS_ASSIM" ]]; then
  # First-run end offset (hours before T0): AnA window is 3h (1+2) so its first
  # run ends at T0-2; Extended AnA window is 28h (24+4) so its first run ends at T0-4.
  if [[ ${CASETYPE} == "CONUS_EXT_ANALYSIS_ASSIM" ]]; then
    run1_offset=-4
  else
    run1_offset=-2
  fi

  #copy warm states
  cp -r ${DATA}/default/test_bmi/*/state_save_${PDY}${cyc} ${COMOUT}/${cyc}/${CASETYPE}/
  cp -r ${DATA}/default/test_bmi/*/state_save_$($NDATE ${run1_offset} ${PDY}${cyc}) ${COMOUT}/${cyc}/${CASETYPE}/

  #cat-*.csv and nex-*.csv files
  cp -r ${DATA}/default/test_bmi/*/Output_${PDY}${cyc} ${COMOUT}/${cyc}/${CASETYPE}/
  cp -r ${DATA}/default/test_bmi/*/Output_$($NDATE ${run1_offset} ${PDY}${cyc}) ${COMOUT}/${cyc}/${CASETYPE}/
else
  #T-route output files
  cp ${DATA}/default/test_bmi/*/Output/*.nc ${COMOUT}/${cyc}/${CASETYPE}/
  #cat-*.csv and nex-*.csv files
  cp ${DATA}/default/test_bmi/*/Output/*.csv ${COMOUT}/${cyc}/${CASETYPE}/
fi 
export err=$?; err_chk

msg="Ending $USHnwm/rte-nwm at `date`"

set $setoff
echo ' '
echo -e "\n=====> Ending $0 at : `date`\n"
echo '***********************************'
