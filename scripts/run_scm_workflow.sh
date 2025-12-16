#!/bin/sh

# Only checkout SCM data if it is needed for the requested suites?
# Check if FIX_DATA_DIR is empty
# Add more user options: column area, timestep, vert levs
# Check if build was configured with all requested suites

# List of suites to test
SUITE_LIST='SCM_GFS_v17_p8_ugwpv1'

# List of cases to test - note - forcing data for each case may be in separate directories
# Currently supported: twpice, MAGIC_LEG15A, 
CASE_LIST='MAGIC_LEG15A'

# Platform (Hera/Derecho) and compiler (intel/gnu)
PLATFORM='ursa'
COMPILER='intel'

# Github repo
GIT_URL='https://github.com/NCAR/ccpp-scm.git'
GIT_BRANCH='main'
SCM_DIR='ccpp-scm'

# Build switches
make_build='False'
build_32bit='False'

# Plotting options
PLOT_DIR='plots_test'
OBS_COMPARE='True'

###################################################
# Build SCM for the platform and compilers selected
###################################################

# Define directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR=$BASE_DIR/scm_builds

# Load the SCM environment
MODULE_PATH="$BUILD_DIR/$SCM_DIR/scm/etc/modules"
module use "$MODULE_PATH"
module load "${PLATFORM}_${COMPILER}_spack_stack_1.9.1"
sleep 2

if [ $make_build == 'True' ]; then
  do_build="yes"

  # Check if the build exists
  if [ -d "$BUILD_DIR/$SCM_DIR" ]; then
    echo "Build directory already exists:"
    echo " $BUILD_DIR/$SCM_DIR"

    # If the build exists, promt user whether to rebuild or skip build
    printf "Overwrite and rebuild? (y/n): "
    read -r response

    case "$response" in
        [Yy]* )
            echo "Removing existing build."
            rm -rf "$BUILD_DIR/$SCM_DIR/scm/bin"
            ;;
        [Nn]* )
            echo "Existing build preserved. Skipping build."
            do_build="no"
            ;;
        * )
            echo "Invalid response. Exiting."
            exit 1
            ;;
    esac
  fi

  # Build the ccpp-scm if requested
  if [ "$do_build" = "yes" ]; then

    # Check if the scm_builds directory exists. If not create it
    if [ ! -d "$BUILD_DIR/$SCM_DIR" ]; then
      if [ ! -d "$BUILD_DIR" ]; then
        mkdir -p $BUILD_DIR
      fi
      cd $BUILD_DIR
      git clone --recursive -b $GIT_BRANCH $GIT_URL $SCM_DIR
    fi

    cd $BUILD_DIR/$SCM_DIR/scm && mkdir bin && cd bin

    # Build with single precision if requested
    if [ $build_32bit == 'True' ]; then
      cmake -DCCPP_SUITES="${SUITE_LIST// /,}" -D32BIT=ON ../src
    else
      cmake -DCCPP_SUITES="${SUITE_LIST// /,}" ../src
    fi
    make -j4
  fi
fi

################################
# Ensure SCM data is checked out
################################
FIX_DATA_DIR=$BASE_DIR/fix_data

if [ ! -d $FIX_DATA_DIR ]; then
  mkdir -p $FIX_DATA_DIR
  cd $BUILD_DIR/$SCM_DIR
  ./contrib/get_all_static_data.sh
  ./contrib/get_thompson_tables.sh
  ./contrib/get_tempo_data.sh
  ./contrib/get_rrtmgp.sh
  ./contrib/get_aerosol_climo.sh
  mv scm/data/comparison_data \
     scm/data/physics_input_data \
     scm/data/processed_case_input \
     scm/data/raw_case_input \
     $FIX_DATA_DIR
fi
ln -sf $FIX_DATA_DIR/* $BUILD_DIR/$SCM_DIR/scm/data

############################################################
# Run cases
############################################################

# Run through list of cases
for scm_case in $CASE_LIST; do

  echo ${scm_case}
  # Reset each loop
  CASE_DATA_DIR=""

  # Detect if case is MAGIC
  if [[ $scm_case == *"MAGIC"* ]]; then

    # Check if the DEPHY repo exists, if not clone it
    if [ ! -d $BASE_DIR/DEPHY-SCM ]; then
      git clone -b master https://github.com/GdR-DEPHY/DEPHY-SCM $BASE_DIR/DEPHY-SCM
    fi

    # Build the CASE_DATA_DIR for the DEPHY MAGIC cases
    case_prefix=$(echo ${scm_case} | cut -d'_' -f1)
    case_suffix=$(echo ${scm_case} | cut -d'_' -f2)
    CASE_DATA_DIR=${BASE_DIR}/DEPHY-SCM/${case_prefix}/${case_suffix}

    # Check if case namelist exists
    CASE_CONFIG_DIR=${BUILD_DIR}/${SCM_DIR}/scm/etc/case_config
    CASE_NML=${CASE_CONFIG_DIR}/${scm_case}.nml

    # Export variables needed by case_config_template
    export ${scm_case}
    if [ ! -f "$CASE_NML" ]; then
      echo "Case namelist missing: creating $CASE_NML"
      cat <<EOF > "$CASE_NML"
\$case_config
case_name = '${scm_case}',
input_type = 1
lsm_ics = .false.,
do_spinup = .false.,
spinup_timesteps = 0,
reference_profile_choice = 2,
column_area = 1.45E8,
\$end
EOF
    fi
  fi

  # For storing case/suite lists 
  CONFIG_DATASETS=""
  CONFIG_LABELS=""

  # Observation file to use based on case
  if [[ "$scm_case" == MAGIC_LEG15A ]]; then
    OBS_FILE="/scratch3/BMC/gmtb/Tracy.Hertneky/phys_tne/FY25-26/data/${scm_case}_obs.nc"
  elif [[ "$scm_case" == twpice ]]; then
    OBS_FILE="${FIX_DATA_DIR}/raw_case_input/twp180iopsndgvarana_v2.1_C3.c1.20060117.000000.cdf"
  else
    OBS_FILE=""
  fi

  JOB_IDS=()
  BATCH_FILES=()

  # Run through list of suites
  for suite in $SUITE_LIST; do
    echo ${suite}

    # Default output naming
    run_dir="run_${scm_case}_${suite}"
    out_dir="output_${scm_case}_${suite}/output.nc"
    OUTPUT_NC="${BUILD_DIR}/${SCM_DIR}/scm/${run_dir}/${out_dir}"
    CONFIG_DATASETS="${CONFIG_DATASETS}${OUTPUT_NC}, "
    CONFIG_LABELS="${CONFIG_LABELS}${scm_case}_${suite}, "


    # Build the run command, appending CASE_DATA_DIR for DEPHY MAGIC case
    cd "$BUILD_DIR/$SCM_DIR/scm/bin"
    RUN_COMMAND="./run_scm.py -c ${scm_case} -s ${suite} --run_dir ${BUILD_DIR}/${SCM_DIR}/scm/${run_dir} -v"
    if [ -n "${CASE_DATA_DIR}" ]; then
      RUN_COMMAND="${RUN_COMMAND} --case_data_dir ${CASE_DATA_DIR}"
    fi

    # Define output directory and output file
    OUTPUT_DIR="${BUILD_DIR}/${SCM_DIR}/scm/${run_dir}/output_${scm_case}_${suite}"
    OUTPUT_PATH="${OUTPUT_DIR}/output.nc"

    # Check if previous run exists and output.nc is non-zero
    if [ -d "$OUTPUT_DIR" ] && [ -s "$OUTPUT_PATH" ]; then
      echo "===================================================="
      echo " Existing SCM output detected:"
      echo "   File      : $OUTPUT_PATH"
      echo "===================================================="
      printf "Overwrite and rerun case? (y/n):"
      read -r response

      case "$response" in
        [Yy]* )
          echo "Removing existing output directory before rerun..."
          rm -rf "$OUTPUT_DIR"
          ;;
        [Nn]* )
          echo "Skipping rerun for ${scm_case}/${suite}."
          continue
          ;;
        * )
          echo "Invalid response — skipping by default."
          continue
          ;;
      esac

    elif [ -d "$OUTPUT_DIR" ] && [ ! -s "$OUTPUT_PATH" ]; then
      echo ""
      echo "WARNING: Output directory exists but output.nc missing or zero size:"
      echo "  $OUTPUT_PATH"
      echo "Directory will be removed and rerun will proceed."
      rm -rf "$OUTPUT_DIR"
    fi

    # Unique batch file for each submission
    batch_file=$(mktemp "${SCRIPT_DIR}/generated_batch_XXXXXX.sh")

    # Submit jobs for each case/suite combo
    sed "s~RUN_COMMAND~${RUN_COMMAND}~g" $SCRIPT_DIR/batch_template > "$batch_file"
    job_id=$(sbatch "$batch_file" | awk '{print $4}')
    echo "Submitted job $job_id with command: $RUN_COMMAND"
    RUNNING=true

    JOB_IDS+=("$job_id")
    BATCH_FILES+=("$batch_file")
  done

  # Wait for jobs to finish before plotting
  for jid in "${JOB_IDS[@]}"; do
    echo "Waiting for job $jid..."
    while true; do
      state=$(squeue -j "$jid" -h -o %T)
      [[ "$state" == "RUNNING" || "$state" == "PENDING" ]] && sleep 30 || break
    done
    echo "Job $jid finished"
  done

  # Cleanup batch scripts
  for f in "${BATCH_FILES[@]}"; do
    rm -f "$f"
  done

  ######################
  # Run plotting scripts
  ######################

  # Invoke python to get start/end date from case output to pass to the plot config
  # This should be the same for all configs run for the same case.
TIME_INFO=$(python3 - <<EOF
from netCDF4 import Dataset
from datetime import datetime, timedelta

f = Dataset("${OUTPUT_NC}")

y = int(f.variables["init_year"][:])
m = int(f.variables["init_month"][:])
d = int(f.variables["init_day"][:])
H = int(f.variables["init_hour"][:])
M = int(f.variables["init_minute"][:])

init_time = datetime(y, m, d, H, M)

t = f.variables["time_inst"][:]
t = t[t < 1e30]

start_time = init_time + timedelta(seconds=float(t[0]))
end_time   = init_time + timedelta(seconds=float(t[-1]))

print(f"{start_time.year}, {start_time.month}, {start_time.day}, {start_time.hour}")
print(f"{end_time.year}, {end_time.month}, {end_time.day}, {end_time.hour}")
EOF
)

  START_TIME=$(echo "$TIME_INFO" | sed -n '1p')
  END_TIME=$(echo "$TIME_INFO" | sed -n '2p')
  if [[ $scm_case == *"MAGIC_LEG15A"* ]]; then
    START_TIME="2013, 7, 21, 0, 0"
    END_TIME="2013, 7, 24, 23, 59"
  fi

  # Export variables needed for plot_config_template
  export CONFIG_DATASETS
  export CONFIG_LABELS
  export PLOT_DIR
  export OBS_FILE
  export OBS_COMPARE
  export START_TIME
  export END_TIME

  # Plot config template
  PLOT_TEMPLATE="${BASE_DIR}/scripts/plot_config_template.ini"

  # Create the plot config from the template
  if [ ! -d ${BASE_DIR}/scm_plots ]; then
    mkdir -p ${BASE_DIR}/scm_plots
  fi
  PLOT_CONFIG="${BASE_DIR}/scm_plots/${scm_case}.ini"
  envsubst < "$PLOT_TEMPLATE" > "$PLOT_CONFIG"
  echo "Created plot config: $PLOT_CONFIG"

  # Move to the plot directory to run the plots
  cd ${BASE_DIR}/scm_plots

  # Copy python plotting script to run directory
  cp ${SCRIPT_DIR}/scm_analysis.py ${BASE_DIR}/scm_plots
  cp ${SCRIPT_DIR}/scm_read_obs.py ${BASE_DIR}/scm_plots
  cp ${BUILD_DIR}/${SCM_DIR}/scm/etc/scripts/scm_plotting_routines.py ${BASE_DIR}/scm_plots
  cp ${BUILD_DIR}/${SCM_DIR}/scm/etc/scripts/forcing_file_common.py ${BASE_DIR}/scm_plots
  cp ${BUILD_DIR}/${SCM_DIR}/scm/etc/scripts/configspec.ini ${BASE_DIR}/scm_plots

  # Run the python plotting script
  python3 ${BASE_DIR}/scm_plots/scm_analysis.py $PLOT_CONFIG

done
