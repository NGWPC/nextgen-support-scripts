#!/bin/bash

#SBATCH -J Perf_scale_test 
#SBATCH -o Perf_scale_test_%j.log
#SBATCH -t 02:00:00
#SBATCH --nodes 1
#SBATCH --exclusive
#SBATCH --ntasks-per-node=18

function run_vpu()
{
  local VPU=$1
  local NPROCS=$2
  local TEST_FORM_ASSIGN_VPU="${INSTALLED_REGIONALIZATION_RESULTS}/vpu_${VPU}/formulation_assignment.csv"
  local TEST_CAT_GRP_VPU="${INSTALLED_REGIONALIZATION_RESULTS}/vpu_${VPU}/catchment_groups.csv"

  source my_run.sh && docker_run python -um "ngen_rte.run_regionalization_standalone" \
	     -n ${NPROCS} -fconfig "short_range" -dt "2026-03-30 06:00:00" \
	     -rname "default_short" -nwmout  --vpu ${VPU} \
       	-faf "${TEST_FORM_ASSIGN_VPU}" \
       	-cgf  "${TEST_CAT_GRP_VPU}" --output_format NetCDF --checkpoint_interval 1 
}

function parallel_run_vpu()
{
   nprocs=$1
   export CPUSET_CPUS="$2"

   #clean up first
   sudo rm -rf ${RUN_NGEN_ROOT__HOST}/regionalization/*

   # Record start time
   start_time=$(date +%s)

   # --- 1 processor ---
   VPU="03S"

   run_vpu ${VPU} ${nprocs}

   # Record end time
   end_time=$(date +%s)

   total_time_secs=$((end_time - start_time))

   # Output results
   echo $total_time_secs
}

set -euo pipefail

workdir=$(pwd)

sudo systemctl start docker 

cd ../ush/nwm-rte
./ngen_rte_build.sh

# use the working directory on local disk
#export RUN_NGEN_ROOT__HOST=${HOME}/test/tmp
export RUN_NGEN_ROOT__HOST=/media/test/tmp
#export RUN_NGEN_ROOT__HOST=/lfs/h1/ops/prod/owp/test/tmp

cd ${workdir}
#prepare RTE to run
source ../ush/nwm-rte/config.bashrc

#
# Update the run.sh script
#
RTE=$(pwd)/../ush/nwm-rte
sed  -e "s|\$(pwd)/bin_mounted/|$RTE/bin_mounted/|" \
	-e "/^\s\+time sudo docker/a \ \ \ \ \ \$\{CPUSET_CPUS:+--cpuset-cpus=\"\$\{CPUSET_CPUS\}\"\}  \\\\" \
	-e "s|\$(pwd)|$RUN_NGEN_ROOT__HOST|" \
	-e "/source config.bashrc/d" ../ush/nwm-rte/run.sh > my_run.sh

sudo mkdir -p $RUN_NGEN_ROOT__HOST/logs/docker/run
sudo mkdir -p $RUN_NGEN_ROOT__HOST/logs/rte


DATA="# nprocs  wall clock time (secs)"
################################################
#
# Parallel execution of 03S
#
# 1 processor 

echo "Running VPU 03S short range on processor 0 ..."
total_time=$(parallel_run_vpu 1 "0")
echo "Time of the 1 processor: ${total_time} seconds"
# Convert total time to H:M:S
hours=$((total_time / 3600))
minutes=$(((total_time % 3600) / 60))
seconds=$((total_time % 60))
printf "Total time of 1 processor start to end: %02d:%02d:%02d (H:M:S)\n" "$hours" "$minutes" "$seconds"
DATA+=$'\n'"1  $total_time"

# 2 processors
echo "Running VPU 03S short range on 2 processors ..."
total_time=$(parallel_run_vpu 2 "0,1")
echo "Time of the 2 processors: ${total_time} seconds"
# Convert total time to H:M:S
hours=$((total_time / 3600))
minutes=$(((total_time % 3600) / 60))
seconds=$((total_time % 60))
printf "Total time of 2 processors start to end: %02d:%02d:%02d (H:M:S)\n" "$hours" "$minutes" "$seconds"
DATA+=$'\n'"2  $total_time"

# 4 processors
echo "Running VPU 03S short range on 4 processors ..."
total_time=$(parallel_run_vpu 4 "0,1,2,3")
echo "Time of the 4 processors: ${total_time} seconds"
# Convert total time to H:M:S
hours=$((total_time / 3600))
minutes=$(((total_time % 3600) / 60))
seconds=$((total_time % 60))
printf "Total time of 4 processors start to end: %02d:%02d:%02d (H:M:S)\n" "$hours" "$minutes" "$seconds"
DATA+=$'\n'"4  $total_time"

# 8 processors
echo "Running VPU 03S short range on 8 processors ..."
total_time=$(parallel_run_vpu 8 "0,1,2,3,4,5,6,7")
echo "Time of the 8 processors: ${total_time} seconds"
# Convert total time to H:M:S
hours=$((total_time / 3600))
minutes=$(((total_time % 3600) / 60))
seconds=$((total_time % 60))
printf "Total time of 8 processors start to end: %02d:%02d:%02d (H:M:S)\n" "$hours" "$minutes" "$seconds"
DATA+=$'\n'"8  $total_time"

# 12 processors
echo "Running VPU 03S short range on 12 processors ..."
total_time=$(parallel_run_vpu 12 "0,1,2,3,4,5,6,7,8,9,10,11")
echo "Time of the 12 processors: ${total_time} seconds"
# Convert total time to H:M:S
hours=$((total_time / 3600))
minutes=$(((total_time % 3600) / 60))
seconds=$((total_time % 60))
printf "Total time of 12 processors start to end: %02d:%02d:%02d (H:M:S)\n" "$hours" "$minutes" "$seconds"
DATA+=$'\n'"12  $total_time"

# 16 processors
echo "Running VPU 03S short range on 16 processors ..."
total_time=$(parallel_run_vpu 16 "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14.15")
echo "Time of the 16 processors: ${total_time} seconds"
# Convert total time to H:M:S
hours=$((total_time / 3600))
minutes=$(((total_time % 3600) / 60))
seconds=$((total_time % 60))
printf "Total time of 16 processors start to end: %02d:%02d:%02d (H:M:S)\n" "$hours" "$minutes" "$seconds"
DATA+=$'\n'"16  $total_time"

echo "Creating the runtime vs. number of cores figure ..."

tempdata=$(printf "%b" "$DATA")

  gnuplot -persist <<-EOFMarker
      \$Mydata << EOD
$tempdata
EOD
      # Set terminal to png or pdf for output
      set terminal pngcairo enhanced font 'Arial, 12'
      set output 'VPU_mpi_03S_runtime.png'

      # Set title and labels
      set title "MPI parallel number of cores vs runtime (03S)"
      set xlabel 'Number of cores'
      set ylabel "Wall clock time (mins) " offset 0,0,0
      unset key
      set yrange [0:*]
      set grid

      # Plot data from file
      plot \$Mydata using 1:(\$2/60) with linespoints

EOFMarker

exit 0
