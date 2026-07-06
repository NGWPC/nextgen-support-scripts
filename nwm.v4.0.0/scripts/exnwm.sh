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
        return 1
    fi

    local log_file
    log_file=$(ls -t "${log_dir}"/rte_*.log 2>/dev/null | head -1)
    if [[ -z "${log_file}" ]]; then
        echo "ERROR: No RTE log files found in ${log_dir}" >&2
        return 1
    fi
    echo "RTE log scan: scanning ${log_file}"

    local error_count=0 warning_count=0 info_count=0
    local file_warnings file_errors n

    n=$(grep -cE '^\S+[[:space:]]+RTE[[:space:]]+INFO[[:space:]]' \
        "${log_file}" 2>/dev/null) || true
    info_count=${n:-0}

    file_warnings=$(grep -E '^\S+[[:space:]]+RTE[[:space:]]+WARNING[[:space:]]' \
                    "${log_file}" 2>/dev/null) || true
    if [[ -n "${file_warnings}" ]]; then
        echo "${file_warnings}"
        n=$(grep -cE '^\S+[[:space:]]+RTE[[:space:]]+WARNING[[:space:]]' \
            "${log_file}" 2>/dev/null) || true
        warning_count=${n:-0}
    fi

    file_errors=$(grep -E '^\S+[[:space:]]+RTE[[:space:]]+(ERROR|FATAL|CRITICAL|SEVERE)[[:space:]]' \
                  "${log_file}" 2>/dev/null) || true
    if [[ -n "${file_errors}" ]]; then
        echo "${file_errors}"
        n=$(grep -cE '^\S+[[:space:]]+RTE[[:space:]]+(ERROR|FATAL|CRITICAL|SEVERE)[[:space:]]' \
            "${log_file}" 2>/dev/null) || true
        error_count=${n:-0}
    fi

    echo "RTE log scan: ${info_count} INFO message(s) found in ${log_dir}."
    if [[ ${warning_count} -gt 0 ]]; then
        echo "RTE log scan: ${warning_count} WARNING(s) found in ${log_dir}."
    fi
    if [[ ${error_count} -gt 0 ]]; then
        echo "RTE log scan: ${error_count} ERROR/FATAL/CRITICAL/SEVERE line(s) found in ${log_dir}." >&2
        return 1
    fi
    set $seton
}

set +e   # Disable exit-on-error
# Append VPU region to case type if provided (to support multiple VPU runs in parallel)
RUN_CASETYPE="${CASETYPE}"
VPU_ARG=""
SUBREGION="01123000"
export VPU=$(ecflow_client --query variable ${ECF_NAME}:VPU)
if [[ "${VPU}" != "NONE" ]]; then
  RUN_CASETYPE="${CASETYPE}_${VPU}"
  VPU_ARG="--vpu ${VPU}"
  REGION_SUBDIR="vpu_${VPU}"
  SUBDIR=${VPU}
else
  REGION_SUBDIR=${SUBREGION}
  SUBDIR=${SUBREGION}
fi

# Set paths to static regionalization input files
# This is the path inside the container
REGION_DATA_ROOT="/ngen-app/ngen-python/lib/python3.11/site-packages/mswm/example_inputs/regionalization/${REGION_SUBDIR}"
FORM_ASSIGN_FILE="${REGION_DATA_ROOT}/formulation_assignment.csv"
CAT_GRP_FILE="${REGION_DATA_ROOT}/catchment_groups.csv"

# configure and run RTE
if [[ ${CASETYPE} == "CONUS_ANALYSIS_ASSIM" ]]; then
  python3.12  ${USHnwm}/nwm-realtime/nwm_realtime_fcst.py    \
    --config-name "AnA"                                  \
    --domain "CONUS"                                     \
    --t0 "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00" \
    --package-dir ${HOMEnwm}                             \
    --working-dir ${DATA}                                \
    --comout ${COMOUT}                                   \
    --previous-day-comout ${COMOUTm1}                    \
    --form-assign-file "${FORM_ASSIGN_FILE}"             \
    --cat-grp-file "${CAT_GRP_FILE}"                     \
    ${VPU_ARG}
elif [[ ${CASETYPE} == "CONUS_SHORT_RANGE" ]]; then
  python3.12  ${USHnwm}/nwm-realtime/nwm_realtime_fcst.py    \
    --config-name "Short_Range"                          \
    --domain "CONUS"                                     \
    --t0 "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00" \
    --package-dir ${HOMEnwm}                             \
    --working-dir ${DATA}                                \
    --comout ${COMOUT}                                   \
    --previous-day-comout ${COMOUTm1}                    \
    --form-assign-file "${FORM_ASSIGN_FILE}"             \
    --cat-grp-file "${CAT_GRP_FILE}"                     \
    ${VPU_ARG}
elif [[ ${CASETYPE} == "CONUS_EXT_ANALYSIS_ASSIM" ]]; then
  export cyc=16
  python3.12  ${USHnwm}/nwm-realtime/nwm_realtime_fcst.py    \
    --config-name "Extended_AnA"                         \
    --domain "CONUS"                                     \
    --t0 "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00" \
    --package-dir ${HOMEnwm}                             \
    --working-dir ${DATA}                                \
    --comout ${COMOUT}                                   \
    --previous-day-comout ${COMOUTm1}                    \
    --form-assign-file "${FORM_ASSIGN_FILE}"             \
    --cat-grp-file "${CAT_GRP_FILE}"                     \
    ${VPU_ARG}
fi

check_rte_logs
export err=$?; err_chk
if [ "$err" -ne 0 ]; then
    ecflow_client --alter=change variable PRE_WORKDIR "${DATA}" ${ECF_NAME}
    exit 1
fi

set -e   # stop on errors 

if [ ! -d ${COMOUT}/${cyc}/${RUN_CASETYPE} ]; then
	mkdir -p ${COMOUT}/${cyc}/${RUN_CASETYPE}
fi

if [ ! -d ${COMOUT}/logs/${cyc}/${RUN_CASETYPE} ]; then
	mkdir -p ${COMOUT}/logs/${cyc}/${RUN_CASETYPE}
fi

#NGen logs
cp ${DATA}/regionalization/*/${SUBDIR}/*.log ${COMOUT}/logs/${cyc}/${RUN_CASETYPE}/

#log messages from MSWM
cp -r ${DATA}/logs/* ${COMOUT}/logs/${cyc}/${RUN_CASETYPE}/

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
  cp -r ${DATA}/regionalization/*/${SUBDIR}/state_save_${PDY}${cyc} ${COMOUT}/${cyc}/${RUN_CASETYPE}/
  cp -r ${DATA}/regionalization/*/${SUBDIR}/state_save_$($NDATE ${run1_offset} ${PDY}${cyc}) ${COMOUT}/${cyc}/${RUN_CASETYPE}/

  #cat-*.csv and nex-*.csv files
  cp ${DATA}/regionalization/*/${SUBDIR}/Output_${PDY}${cyc}/catchment_output.nc \
	  ${COMOUT}/${cyc}/${RUN_CASETYPE}/catchment_output_${PDY}${cyc}00.nc
  cp ${DATA}/regionalization/*/${SUBDIR}/Output_$($NDATE ${run1_offset} ${PDY}${cyc})/catchment_output.nc  \
          ${COMOUT}/${cyc}/${RUN_CASETYPE}/catchment_output_$($NDATE ${run1_offset} ${PDY}${cyc})00.nc
  cp ${DATA}/regionalization/*/${SUBDIR}/Output_${PDY}${cyc}/troute_output_${PDY}${cyc}00.nc \
	  ${COMOUT}/${cyc}/${RUN_CASETYPE}/
  cp ${DATA}/regionalization/*/${SUBDIR}/Output_$($NDATE ${run1_offset} ${PDY}${cyc})/troute_output_$($NDATE ${run1_offset} ${PDY}${cyc})00.nc  \
          ${COMOUT}/${cyc}/${RUN_CASETYPE}/
else
  #catchment and T-route output files
  cp ${DATA}/regionalization/*/${SUBDIR}/Output/catchment_output.nc \
	  ${COMOUT}/${cyc}/${RUN_CASETYPE}/catchment_output_${PDY}${cyc}00.nc
  cp ${DATA}/regionalization/*/${SUBDIR}/Output/troute_output_$($NDATE 1 ${PDY}${cyc})00.nc  \
          ${COMOUT}/${cyc}/${RUN_CASETYPE}/
fi 
export err=$?; err_chk

msg="Ending $USHnwm/rte-nwm at `date`"

set $setoff
echo ' '
echo -e "\n=====> Ending $0 at : `date`\n"
echo '***********************************'
