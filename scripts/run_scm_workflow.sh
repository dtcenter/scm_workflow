#!/bin/bash

# List of cases to test
# Currently supported: twpice, MAGIC_LEG12A, MAGIC_LEG15A, MOSAiC-AMPS, MOSAiC-SS, COMBLE, MPACE_REF
CASE_LIST='MOSAiC-AMPS COMBLE'

# List of suites to test
SUITE_LIST='SCM_GFS_v17_p8_ugwpv1 SCM_GFS_v17_p8_ugwpv1_tempo SCM_GFS_v17_p8_ugwpv1_nosh SCM_GFS_v17_p8_ugwpv1_tempo_nosh'

# List of column areas in m^2
# *If left empty, uses default in case config nml
COLUMN_AREAS=''

# List of time steps and respecitve inner timesteps and output frequencies
TIME_STEPS=(150)
DT_INNER=(75)
OUT_FREQS=(4)
DIAG_FREQS=(4)

# Platform (ursa/derecho) and compiler (intel/gnu)
PLATFORM='ursa'
COMPILER='gnu'

# Flag for type of SCM repo to use (github/local)
scm_type='local'

# If using SMC Github repo, supply the url and branch
GIT_URL='https://github.com/NCAR/ccpp-scm.git'
GIT_BRANCH='main'
scm_tag='test'

# If using local SCM repo, supply the directory path
local_scm_dir='/scratch3/BMC/gmtb/Tracy.Hertneky/phys_tne/FY25-26/ccpp-scm_tempov3'

# Build switches
make_build='True'
build_32bit='False'

# Run option to skip existing runs or not
rerun_cases='False'

# Tag used for directory naming for the set of scm runs

# Plotting options
plot_tag='noshal_comp_150_75'
PLOT_DIR=plots_${plot_tag}
# Cases that do not support obs comparisons are hard-coded to False
OBS_COMPARE='True'
TS_RESAMPLE='True'

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
  SCM_DIR=$BUILD_DIR/ccpp-scm-$scm_tag
elif [ $scm_type == 'local' ]; then
  SCM_DIR=$local_scm_dir
fi

SUITE_BUILD_LIST="$SUITE_LIST"
for s in $SUITE_LIST; do
  SUITE_BUILD_LIST="$SUITE_BUILD_LIST ${s}_ps"
done

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
        git clone --recursive -b $GIT_BRANCH $GIT_URL ccpp-scm-$scm_tag
      fi
    fi

    # Load the SCM environment
    module purge
    MODULE_PATH="$SCM_DIR/scm/etc/modules"
    module use "$MODULE_PATH"
    #module load "${PLATFORM}_${COMPILER}"
    module load "${PLATFORM}_${COMPILER}_spack_stack_1.9.1"
    sleep 2

    cd $SCM_DIR/scm && mkdir bin && cd bin

    # Build with single precision if requested
    if [ $build_32bit == 'True' ]; then
      cmake -DCCPP_SUITES="${SUITE_BUILD_LIST// /,}" -D32BIT=ON ../src
    else
      cmake -DCCPP_SUITES="${SUITE_BUILD_LIST// /,}" ../src
    fi
    make -j8
  fi
fi

################################
# Ensure SCM data is checked out
################################
FIX_DATA_DIR=$BASE_DIR/fix_data

if [ ! -d $FIX_DATA_DIR ]; then
  mkdir -p $FIX_DATA_DIR
  cd $SCM_DIR
  module purge
  ./contrib/get_all_static_data.sh
  ./contrib/get_thompson_tables.sh
  ./contrib/get_tempo_data.sh
  ./contrib/get_rrtmgp_data.sh
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

  # Detect if case is from DEPHY repo
  if [[ $scm_case == *"MAGIC"* || $scm_case == *"MPACE"* ]]; then
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

  # If cloumn area isn't set, use default for each case
  if [[ -z "$COLUMN_AREAS" ]]; then
    use_default_area='True'
    if [[ $scm_case == *"MAGIC"* || $scm_case == *"MPACE"* || $scm_case == "COMBLE" ]]; then
      COLUMN_AREAS='1.45E8'
    elif [[ $scm_case == "twpice" || $scm_case == *"MOSAiC"* ]]; then
      COLUMN_AREAS='2E9'
    fi
  fi

  # For storing case/suite lists 
  CONFIG_DATASETS=""
  CONFIG_LABELS=""

  JOB_IDS=()
  BATCH_FILES=()

  # Load the SCM environment
  module purge
  MODULE_PATH="$SCM_DIR/scm/etc/modules"
  module use "$MODULE_PATH"
  #module load "${PLATFORM}_${COMPILER}"
  module load "${PLATFORM}_${COMPILER}_spack_stack_1.9.1"
  sleep 5

  # Build captions
  read -ra SUITES <<< "$SUITE_LIST"
  read -ra AREAS <<< "$COLUMN_AREAS"

  caption=()
  if [ ${#SUITES[@]} -eq 1 ]; then
    caption+=("Suite: ${SUITES[0]}")
  fi
  if [ ${#AREAS[@]} -eq 1 ]; then
    area=$(awk -v a="${AREAS[0]}" 'BEGIN { printf "%.2f", sqrt(a)/1000 }')
    caption+=(" Area: ${area}km")
  fi
  first=${TIME_STEPS[0]}
  for v in "${TIME_STEPS[@]}"; do
    [[ "$v" != "$first" ]] && first="" && break
  done
  [[ -n "$first" ]] && caption+=(" dt: ${first}s")
  first=${DT_INNER[0]}
  for v in "${DT_INNER[@]}"; do
    [[ "$v" != "$first" ]] && first="" && break
  done
  [[ -n "$first" ]] && caption+=(" dti: ${first}s")
  captions=$(IFS=', '; echo "${caption[*]}")

  # Run through list of suites
  for suite in $SUITE_LIST; do

    # Run through list of column areas
    for column_area in $COLUMN_AREAS; do
      column_dx=$(awk -v a="${column_area}" 'BEGIN { printf "%.2f", sqrt(a)/1000 }')

      # Loop through time steps
      for ((n=0; n<${#TIME_STEPS[@]}; n++)); do

	timestep="${TIME_STEPS[n]}"
	dti="${DT_INNER[n]}"
        out_freq="${OUT_FREQS[n]}"
        diag_freq="${DIAG_FREQS[n]}"

        # Export variables needed by case_config_template
        export scm_case
        export column_area

        NML_TEMPLATE="${BASE_DIR}/scripts/case_config_template.nml"
        envsubst '${scm_case} ${column_area}' < "$NML_TEMPLATE" > "$CASE_NML"
        echo "Created case config: $CASE_NML"

        export dti

        # Build labels
	label=()
        if [ ${#SUITES[@]} -gt 1 ]; then
          label+=("$suite")
        fi
	if [ ${#AREAS[@]} -gt 1 ]; then
          label+=("${column_dx}km")
        fi
        dt_unique=$(printf "%s\n" "${TIME_STEPS[@]}" | sort -u | wc -l)
	if [ "$dt_unique" -gt 1 ]; then
          label+=("dt${timestep}s")
        fi
        dti_unique=$(printf "%s\n" "${DT_INNER[@]}" | sort -u | wc -l)
	if [ "$dti_unique" -gt 1 ]; then
          label+=("dti${dti}s")
        fi

        # Default output naming
        run_dir="run_${scm_case}_${suite}_area${column_dx}km_dt${timestep}s_dti${dti}s"
        run_path="${run_dir}/output_${scm_case}_${suite}/output.nc"
        OUTPUT_DIR="${BASE_DIR}/scm_runs/${scm_tag}/${scm_case}/${suite}"
        OUTPUT_PATH="${OUTPUT_DIR}/area${column_dx}km_dt${timestep}s_dti${dti}s_output.nc"
        CONFIG_DATASETS="${CONFIG_DATASETS}${OUTPUT_PATH}, "
        CONFIG_LABELS="${CONFIG_LABELS}${label[@]}, "

        # Build the run command, appending CASE_DATA_DIR for DEPHY repo cases
        cd "$SCM_DIR/scm/bin"
	cp ${SCRIPT_DIR}/run_scm.py $SCM_DIR/scm/src/run_scm_wf.py
	ln -sf $SCM_DIR/scm/src/run_scm_wf.py .
        RUN_COMMAND="./run_scm_wf.py -c ${scm_case} -s ${suite} -dt ${timestep} --n_itt_out ${out_freq} --n_itt_diag ${diag_freq} --run_dir $SCM_DIR/scm/${run_dir} -v"
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
            rm -rf "$SCM_DIR/scm/${run_dir}" "${OUTPUT_PATH}"
          fi
        fi

        # Run all cases that do not exist
        if [ ! -d "${OUTPUT_DIR}" ] || [ ! -s "$OUTPUT_PATH" ]; then
	  # Unique batch file for each submission
          batch_file=$(mktemp "${SCRIPT_DIR}/generated_batch_XXXXXX.sh")

          # Submit jobs for each case/suite combo
          if [ $PLATFORM == 'ursa' ]; then 
            sed "s~RUN_COMMAND~${RUN_COMMAND}~g" $SCRIPT_DIR/ursa_template > "$batch_file"
            job_id=$(sbatch "$batch_file" | awk '{print $4}')
            echo "Submitted job $job_id with command: $RUN_COMMAND"
          elif [ $PLATFORM == 'derecho' ]; then
            sed "s~RUN_COMMAND~${RUN_COMMAND}~g" $SCRIPT_DIR/derecho_template > "$batch_file"
            job_id=$(qsub -v dti="$dti",column_area="$column_area",scm_case="$scm_case" "$batch_file")
            echo "Submitted job $job_id with command: $RUN_COMMAND"
          fi
          RUNNING=true
	  sleep 30

          JOB_IDS+=("$job_id")
          BATCH_FILES+=("$batch_file")
        fi
        #n=$((n+1))
      done
    done
  done

  # Wait for jobs to finish before plotting
  for jid in "${JOB_IDS[@]}"; do
    echo "Waiting for job $jid..."
    while true; do
      if [ $PLATFORM == 'ursa' ]; then
        state=$(squeue -j "$jid" -h -o %T)
        [[ "$state" == "RUNNING" || "$state" == "PENDING" ]] && sleep 30 || break
      elif [ $PLATFORM == 'derecho' ]; then
        state=$(qstat -f "$jid" | awk -F'= ' '/job_state/ {print $2}')
        [[ "$state" == "R" || "$state" == "Q" ]] && sleep 30 || break
      fi
    done
    echo "Job $jid finished"
  done

  # Cleanup batch scripts
  for f in "${BATCH_FILES[@]}"; do
    rm -f "$f"
  done

  # Move all runs to a general run directory
  for suite in $SUITE_LIST; do
    if [[ ! -d "${BASE_DIR}/scm_runs/${scm_tag}/${scm_case}/${suite}" ]]; then
      mkdir -p ${BASE_DIR}/scm_runs/${scm_tag}/${scm_case}/${suite}
    fi
    for column_area in $COLUMN_AREAS; do
      for ((n=0; n<${#TIME_STEPS[@]}; n++)); do
        column_dx=$(awk -v a="${column_area}" 'BEGIN { printf "%.2f", sqrt(a)/1000 }')
        timestep="${TIME_STEPS[n]}"
	dti="${DT_INNER[n]}"
        cp $SCM_DIR/scm/run_${scm_case}_${suite}_area${column_dx}km_dt${timestep}s_dti${dti}s/output_${scm_case}_${suite}/output.nc ${BASE_DIR}/scm_runs/${scm_tag}/${scm_case}/${suite}/area${column_dx}km_dt${timestep}s_dti${dti}s_output.nc
        cp $SCM_DIR/scm/run_${scm_case}_${suite}_area${column_dx}km_dt${timestep}s_dti${dti}s/output_${scm_case}_${suite}/${scm_case}_${suite}.nml ${BASE_DIR}/scm_runs/${scm_tag}/${scm_case}/${suite}
      done
    done
  done
  if [[ $use_default_area == 'True' ]]; then
    COLUMN_AREAS=''
  fi

  ######################
  # Run plotting scripts
  ######################

  # Parameters used by plotting routine for each case
  if [[ "$scm_case" == MAGIC_LEG12A ]]; then
    OBS_FILE=""
    START_TIME="2013, 6, 8, 17, 45"
    END_TIME="2013, 6, 8, 21, 45"
    OBS_COMPARE='False'
    TS_RESAMPLE='False'
  elif [[ "$scm_case" == MAGIC_LEG15A ]]; then
    OBS_FILE="/scratch3/BMC/gmtb/Tracy.Hertneky/phys_tne/FY25-26/data/${scm_case}_obs.nc"
    START_TIME="2013, 7, 21, 0, 0"
    END_TIME="2013, 7, 24, 23, 59"
    OBS_COMPARE='True'
    TS_RESAMPLE='True'
  elif [[ "$scm_case" == twpice ]]; then
    OBS_FILE="${FIX_DATA_DIR}/raw_case_input/twp180iopsndgvarana_v2.1_C3.c1.20060117.000000.cdf"
    START_TIME="2006, 1, 20, 0"
    END_TIME="2006, 1, 23, 0"
    OBS_COMPARE='True'
    TS_RESAMPLE='True'
  elif [[ "$scm_case" == MOSAiC-AMPS ]]; then
    OBS_FILE="${FIX_DATA_DIR}/raw_case_input/MOSAiC_31Oct20190Z_raw.nc"
    START_TIME="2019, 11, 1, 0"
    END_TIME="2019, 11, 2, 0"
    OBS_COMPARE='True'
    TS_RESAMPLE='True'
  elif [[ "$scm_case" == MOSAiC-SS ]]; then
    OBS_FILE="${FIX_DATA_DIR}/raw_case_input/MOSAiC_2Mar20200Z_raw.nc"
    START_TIME="2020, 3, 4, 0"
    END_TIME="2020, 3, 5, 0"
    OBS_COMPARE='True'
    TS_RESAMPLE='True'
  elif [[ "$scm_case" == COMBLE ]]; then
    OBS_FILE=""
    START_TIME="2020, 3, 13, 1"
    END_TIME="2020, 3, 13, 18"
    OBS_COMPARE='False'
    TS_RESAMPLE='False'
  elif [[ "$scm_case" == MPACE_REF ]]; then
    OBS_FILE=""
    START_TIME="2004, 10, 9, 17"
    END_TIME="2004, 10, 10, 17"
    OBS_COMPARE='False'
    TS_RESAMPLE='False'
  else
    OBS_FILE=""
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
  export TS_RESAMPLE
  export START_TIME
  export END_TIME
  export scm_case
  export captions

  # Plot config template
  PLOT_TEMPLATE="${BASE_DIR}/scripts/plot_config_template.ini"

  # Create the plot config from the template
  if [ ! -d ${BASE_DIR}/docs/scm_plots ]; then
    mkdir -p ${BASE_DIR}/docs/scm_plots
  fi
  PLOT_CONFIG="${BASE_DIR}/docs/scm_plots/${scm_case}.ini"
  envsubst < "$PLOT_TEMPLATE" > "$PLOT_CONFIG"
  echo "Created plot config: $PLOT_CONFIG"

  # Move to the plot directory to run the plots
  cd ${BASE_DIR}/docs/scm_plots

  # Copy python plotting script to run directory
  cp ${SCRIPT_DIR}/scm_analysis.py ${BASE_DIR}/docs/scm_plots
  cp ${SCRIPT_DIR}/scm_read_obs.py ${BASE_DIR}/docs/scm_plots
  cp ${SCRIPT_DIR}/scm_plotting_routines.py ${BASE_DIR}/docs/scm_plots
  cp $SCM_DIR/scm/etc/scripts/forcing_file_common.py ${BASE_DIR}/docs/scm_plots
  cp $SCM_DIR/scm/etc/scripts/configspec.ini ${BASE_DIR}/docs/scm_plots

  if [ $PLATFORM == 'derecho' ]; then
    module purge
    module load ncarenv
    module load conda
    source "$(conda info --base)/etc/profile.d/conda.sh"
    if ! conda env list | awk '{print $1}' | grep -qx "env_scm_analysis"; then
      echo "Creating conda environment env_scm_analysis"
      conda env create -f "${SCM_DIR}/environment-scm_analysis.yml" -n env_scm_analysis
    else
      echo "Using existing conda environment env_scm_analysis"
    fi
    conda activate env_scm_analysis
  fi

  # Run the python plotting script
  python ${BASE_DIR}/docs/scm_plots/scm_analysis.py $PLOT_CONFIG

  #########################################
  # Setup github pages for displaying plots
  #########################################
  plot_path="${BASE_DIR}/docs/scm_plots/${PLOT_DIR}"
  if [ ! -d ${plot_path} ]; then
    mkdir -p ${plot_path}
  fi
  export plot_path

done

python ${BASE_DIR}/docs/generate_config.py
