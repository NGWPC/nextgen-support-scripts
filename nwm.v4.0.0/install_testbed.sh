#!/usr/bin/env bash

set -xa
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Use default port."
  export ECF_PORT=3141
else
  echo "Use port $1"
  export ECF_PORT=$1
fi 

export PATH=/contrib/software/ecflow/5.15.2/bin:$PATH

PACKAGEROOT=/contrib/lfs/h1/owp/nwm/noscrub/${LOGNAME}/test/packages
PACKAGEDIR=${PACKAGEROOT}/nwm.v4.0.0

if [ ! -d ${PACKAGEDIR} ]; then
  mkdir -p ${PACKAGEDIR}
else
  echo "Installation already exists at ${PACKAGEDIR}, please remove the package (rm -rf ${PACKAGEDIR}) and try again. "
  exit -1
fi

echo "Installing EcFlow/NCO scripts ... "

ln -s ./ecf ${PACKAGEDIR}

PDY=$(date +"%Y%m%d")
sed -i -e "s/Zhengtao\.Cui/${LOGNAME}/" ${PACKAGEDIR}/ecf/nwm.def
sed -i -e "s/repeat date YMD 2026\d+/repeat date YMD ${PDY}/" ${PACKAGEDIR}/ecf/nwm.def

ln -s ./jobs ${PACKAGEDIR}
ln -s ./scripts ${PACKAGEDIR}
ln -s ./ush ${PACKAGEDIR}
ln -s ./versions ${PACKAGEDIR}
ln -s ./prod_envir.2.0.6 ${PACKAGEROOT}
ln -s ./prod_util.v2.0.14 ${PACKAGEROOT}

mkdir -p /lfs/h1/owp/ptmp/${LOGNAME}/test/tmp/nwm/hourly/nwm_analysis_assim
mkdir -p /lfs/h1/owp/ptmp/${LOGNAME}/test/tmp/nwm/hourly/nwm_short_range
mkdir -p /lfs/h1/owp/ptmp/${LOGNAME}/test/tmp/nwm/daily/nwm_extended_analysis_assim

echo "Installing RTE ... "

cd ${PACKAGEDIR}/ush

git clone https://github.com/NGWPC/nwm-rte.git

cd ./nwm-rte/

./setup_clone_repos.sh https
./ngen_rte_build.sh


echo "Installing NWM suit on server ..."

cd ${PACKAGEDIR}/ecf

#terminate the server
#ecflow_client --group="halt=yes; check_pt; terminate=yes"
# check if the server is running
if ecflow_client --ping > /dev/null 2>&1; then
    echo "Server is already running."
else
    echo "Start server on port $ECF_PORT"
    nohup ecflow_server --port=$ECF_PORT &
fi

ecflow_client --delete yes /nwm > /dev/null 2>&1 || true
ecflow_client --load=nwm.def
ecflow_client --begin=nwm
ecflow_client --stats
ecflow_client --get

echo "NWM v4.0.0 is installed successfully on testbed."
