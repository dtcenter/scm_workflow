#!/bin/bash

# Only checkout SCM data if it is needed for the requested suites?
# Check if FIX_DATA_DIR is empty
# Add more user options: vert levs
# Check if build was configured with all requested suites
# If only 1 item in a list add as caption, otherwise add as legend

# List of cases to test - note - forcing data for each case may be in separate directories
# Currently supported: twpice, MAGIC_LEG15A 
CASE_LIST='MAGIC_LEG15A'

# List of suites to test
SUITE_LIST='SCM_GFS_v16 SCM_GFS_v17_p8_ugwpv1'

# List of column areas in m^2 - could also change to column dx in km (more user friendly?)
COLUMN_AREAS='1.45E8'
#COLUMN_AREAS='1.69E8'

# List of time steps
TIME_STEPS='300'
PHYSICS_TIME_STEPS='150'

# Array list of output frequencies (paired with each timestep)
OUT_FREQS=(1)
DIAG_FREQS=(1)

# Platform (Hera/Derecho) and compiler (intel/gnu)
PLATFORM='ursa'
COMPILER='gnu'

# Flag for type of SCM repo to use (github/local)
scm_type='github'

# If using SMC Github repo, supply the url and branch
GIT_URL='https://github.com/NCAR/ccpp-scm.git'
GIT_BRANCH='main'

# If using local SCM repo, supply the directory path
local_scm_dir='/path/to/ccpp-scm'

# Build switches
make_build='True'
build_32bit='False'

# Run option to skip existing runs or not
rerun_cases='False'

# Tag used for directory naming for the set of scm runs
tag='test'

# Plotting options
PLOT_DIR=plots_$tag
OBS_COMPARE='False'

# Option to compare to a local baseline(s)
# Comma-separated if appending more than one baseline
plot_cmp_baseline='False'
baseline_path='/path/to/output.nc'
baseline_label='Baseline'

###################################################
# Build SCM for the platform and compilers selected
###################################################

# Define directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR=$BASE_DIR/scm_builds

if [ $scm_type == 'github' ]; then
  SCM_DIR=$BUILD_DIR/ccpp-scm-$tag
elif [ $scm_type == 'local' ]; then
  SCM_DIR=$local_scm_dir
fi

if [ $make_build == 'True' ]; then
  do_build="yes"

  # Check if the build executable exists
  if [ -f "$SCM_DIR/scm/bin/scm" ]; then
    echo "Build already exists:"
    echo " $SCM_DIR/scm/bin/scm"

    # If the build exists, promt user whether to rebuild or skip build
    printf "Overwrite and rebuild? (y/n): "
    read -r response

    case "$response" in
        [Yy]* )
            echo "Removing existing build."
            rm -rf "$SCM_DIR/scm/bin"
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

    # Check if the github scm_builds directory exists. If not create it
    if [ $scm_type == 'github' ]; then
      if [ ! -d "$SCM_DIR" ]; then
         if [ ! -d "$BUILD_DIR" ]; then
          mkdir -p $BUILD_DIR
        fi
        cd $BUILD_DIR
        git clone --recursive -b $GIT_BRANCH $GIT_URL ccpp-scm-$tag
      fi
    fi

    # Load the SCM environment
    MODULE_PATH="$SCM_DIR/scm/etc/modules"
    module use "$MODULE_PATH"
    module load "${PLATFORM}_${COMPILER}_spack_stack_1.9.1"
    sleep 2

    cd $SCM_DIR/scm && mkdir bin && cd bin

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
  cd $SCM_DIR
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
ln -sf $FIX_DATA_DIR/* $SCM_DIR/scm/data

############################################################
# Run cases
############################################################

# Run through list of cases
for scm_case in $CASE_LIST; do

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
  fi

  # Case config location
  CASE_CONFIG_DIR=$SCM_DIR/scm/etc/case_config
  CASE_NML=${CASE_CONFIG_DIR}/${scm_case}.nml

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

  # Load the SCM environment
  MODULE_PATH="$SCM_DIR/scm/etc/modules"
  module use "$MODULE_PATH"
  module load "${PLATFORM}_${COMPILER}_spack_stack_1.9.1"
  sleep 2

  # Build captions
  read -ra SUITES <<< "$SUITE_LIST"
  read -ra AREAS <<< "$COLUMN_AREAS"
  read -ra DTS <<< "$TIME_STEPS"
  read -ra DTIS <<< "$PHYSICS_TIME_STEPS"

  if [ ${#SUITES[@]} -eq 1 ]; then
    caption+=("Suite: ${SUITES[0]}")
  fi
  if [ ${#AREAS[@]} -eq 1 ]; then
    area=$(awk -v a="${AREAS[0]}" 'BEGIN { printf "%.2f", sqrt(a)/1000 }')
    caption+=(" Area: ${area}km")
  fi
  if [ ${#DTS[@]} -eq 1 ]; then
    caption+=(" dt: ${DTS[0]}s")
  fi
  if [ ${#DTIS[@]} -eq 1 ]; then
    caption+=(" dti: ${DTIS[0]}s")
  fi
  captions=$(IFS=', '; echo "${caption[*]}")

  # Run through list of suites
  for suite in $SUITE_LIST; do

    # Run through list of column areas
    for column_area in $COLUMN_AREAS; do
      column_dx=$(awk -v a="${column_area}" 'BEGIN { printf "%.2f", sqrt(a)/1000 }')

      n=0
      for timestep in $TIME_STEPS; do

        out_freq="${OUT_FREQS[n]}"
        diag_freq="${DIAG_FREQS[n]}"

        # Export variables needed by case_config_template
        export scm_case
        export column_area

        NML_TEMPLATE="${BASE_DIR}/scripts/case_config_template.nml"
        envsubst '${scm_case} ${column_area}' < "$NML_TEMPLATE" > "$CASE_NML"
        echo "Created case config: $CASE_NML"

        # Loop through physics time steps
        for dti in $PHYSICS_TIME_STEPS; do

	  # Change the dt_inner in the physics namelist
 
          # Build labels
	  label=()
          if [ ${#SUITES[@]} -gt 1 ]; then
            label+=("$suite")
          fi
	  if [ ${#AREAS[@]} -gt 1 ]; then
            label+=("dx${column_area}km")
          fi
          if [ ${#DTS[@]} -gt 1 ]; then
            label+=("dt${timestep}s")
          fi
          if [ ${#DTIS[@]} -gt 1 ]; then
            label+=("dti${dti}s")
          fi
          label=$(IFS=', '; echo "${label[*]}")

          # Default output naming
          run_dir="run_${scm_case}_${suite}_area${column_dx}km_dt${timestep}s_dti${dti}s"
          run_path="${run_dir}/output_${scm_case}_${suite}/output.nc"
          OUTPUT_DIR="${BASE_DIR}/scm_runs/${tag}/${scm_case}/${suite}"
          OUTPUT_PATH="${OUTPUT_DIR}/dx${column_dx}km_dt${timestep}s_dti${dti}s_output.nc"
          CONFIG_DATASETS="${CONFIG_DATASETS}${OUTPUT_PATH}, "
          CONFIG_LABELS="${CONFIG_LABELS}${label}, "
          echo ${CONFIG_LABELS[@]}

          # Build the run command, appending CASE_DATA_DIR for DEPHY MAGIC case
          cd "$SCM_DIR/scm/bin"
          RUN_COMMAND="./run_scm.py -c ${scm_case} -s ${suite} -dt ${timestep} --n_itt_out ${out_freq} --n_itt_diag ${diag_freq} --run_dir $SCM_DIR/scm/${run_dir} -v"
	  echo $RUN_COMMAND
          if [ -n "${CASE_DATA_DIR}" ]; then
            RUN_COMMAND="${RUN_COMMAND} --case_data_dir ${CASE_DATA_DIR}"
          fi

          # If directory exists and output.nc are non-zero, check if user wants to rerun cases
          if [ -d "${OUTPUT_DIR}" ] && [ -s "$OUTPUT_PATH" ]; then
            if [[ ${rerun_cases} == "False" ]]; then
              echo "Skipping existing run: ${run_dir}"
            elif [[ ${rerun_cases} == "True" ]]; then
              echo "Overwriting existing run: ${run_dir}"
              rm -rf "$SCM_DIR/scm/${run_dir}"
            fi
          fi

          # Run all cases that do not exist
          if [ ! -d "${OUTPUT_DIR}" ] || [ ! -s "$OUTPUT_PATH" ]; then
	    # Unique batch file for each submission
            batch_file=$(mktemp "${SCRIPT_DIR}/generated_batch_XXXXXX.sh")

            # Submit jobs for each case/suite combo
            sed "s~RUN_COMMAND~${RUN_COMMAND}~g" $SCRIPT_DIR/batch_template > "$batch_file"
            job_id=$(sbatch "$batch_file" | awk '{print $4}')
            echo "Submitted job $job_id with command: $RUN_COMMAND"
            RUNNING=true
	    sleep 10

            JOB_IDS+=("$job_id")
            BATCH_FILES+=("$batch_file")
          fi
        done
      done
      n=$((n+1))
    done
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

  # Move all runs to a general run directory
  for suite in $SUITE_LIST; do
    if [[ ! -d "${BASE_DIR}/scm_runs/${tag}/${scm_case}/${suite}" ]]; then
      mkdir -p ${BASE_DIR}/scm_runs/${tag}/${scm_case}/${suite}
    fi
    for column_area in $COLUMN_AREAS; do
      for timestep in $TIME_STEPS; do
        for dti in $PHYSICS_TIME_STEPS; do
          column_dx=$(awk -v a="${column_area}" 'BEGIN { printf "%.2f", sqrt(a)/1000 }')
          cp $SCM_DIR/scm/run_${scm_case}_${suite}_area${column_dx}km_dt${timestep}s_dti${dti}s/output_${scm_case}_${suite}/output.nc ${BASE_DIR}/scm_runs/${tag}/${scm_case}/${suite}/dx${column_dx}km_dt${timestep}s_dti${dti}s_output.nc
          cp $SCM_DIR/scm/run_${scm_case}_${suite}_area${column_dx}km_dt${timestep}s_dti${dti}s/output_${scm_case}_${suite}/${scm_case}_${suite}.nml ${BASE_DIR}/scm_runs/${tag}/${scm_case}/${suite}
	  # Decide whether to remove the original run directory
          #rm -rf $SCM_DIR/scm/run_${scm_case}_${suite}_area${column_dx}km_dt${timestep}s_dti${dti}s
        done
      done
    done
  done

  ######################
  # Run plotting scripts
  ######################

  # Invoke python to get start/end date from case output to pass to the plot config
  # This should be the same for all configs run for the same case.
  #this should be modified to get the common start date from obs and scm?
#TIME_INFO=$(python3 - <<EOF
#from netCDF4 import Dataset
#from datetime import datetime, timedelta

#f = Dataset("${OUTPUT_PATH}")

#y = int(f.variables["init_year"][:])
#m = int(f.variables["init_month"][:])
#d = int(f.variables["init_day"][:])
#H = int(f.variables["init_hour"][:])
#M = int(f.variables["init_minute"][:])

#init_time = datetime(y, m, d, H, M)

#t = f.variables["time_inst"][:]
#t = t[t < 1e30]

#start_time = init_time + timedelta(seconds=float(t[0]))
#end_time   = init_time + timedelta(seconds=float(t[-1]))

#print(f"{start_time.year}, {start_time.month}, {start_time.day}, {start_time.hour}")
#print(f"{end_time.year}, {end_time.month}, {end_time.day}, {end_time.hour}")
#EOF
#)

#  START_TIME=$(echo "$TIME_INFO" | sed -n '1p')
#  END_TIME=$(echo "$TIME_INFO" | sed -n '2p')
  if [[ $scm_case == *"MAGIC_LEG15A"* ]]; then
    START_TIME="2013, 7, 21, 0, 0"
    END_TIME="2013, 7, 24, 23, 59"
  elif [[ $scm_case == *"twpice"* ]]; then
    START_TIME="2006, 1, 20, 0"
    END_TIME="2006, 1, 23, 0"
  fi

  if [ $plot_cmp_baseline == 'True' ]; then
    CONFIG_DATASETS=$baseline_path${CONFIG_DATASETS}
    CONFIG_LABELS=$baseline_label${CONFIG_LABELS}
  fi
    
  # Export variables needed for templates
  export CONFIG_DATASETS
  export CONFIG_LABELS
  export PLOT_DIR
  export OBS_FILE
  export OBS_COMPARE
  export START_TIME
  export END_TIME
  export scm_case
  export plot_path
  export captions

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
  cp ${SCRIPT_DIR}/scm_plotting_routines.py ${BASE_DIR}/scm_plots
  cp $SCM_DIR/scm/etc/scripts/forcing_file_common.py ${BASE_DIR}/scm_plots
  cp $SCM_DIR/scm/etc/scripts/configspec.ini ${BASE_DIR}/scm_plots

  # Run the python plotting script
  python ${BASE_DIR}/scm_plots/scm_analysis.py $PLOT_CONFIG

  #########################################
  # Setup github pages for displaying plots
  #########################################
  plot_path="${BASE_DIR}/scm_plots/${PLOT_DIR}"
  if [ ! -d ${plot_path} ]; then
    mkdir -p ${plot_path}
  fi

  python ${SCRIPT_DIR}/html/generate_config.py

done
