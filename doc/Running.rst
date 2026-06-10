*****************
Workflow Overview
*****************

The CCPP SCM workflow is version-controlled and available on github. It has been tested on NOAAs pre-
configured platform, Ursa.

To get the CCPP SCM workflow, navigate to the directory where you want to clone the repository and move into
the workflow directory.

.. code-block:: console

   git clone https://github.com/dtcenter/scm_workflow
   cd scm_workflow

After cloning the workflow, only the files within the scripts directory are included. This directory
contains all components of the end-to-end workflow, including scripts for generating configurations
used to host plots on GitHub Pages.

===================
Run Script Overview
===================

Move to the scripts directory and open the ``run_scm_workflow.sh`` script to configure the runs you want
to do.

.. code-block:: console

   cd scripts

All user-modified variables are contained at the top of the ``run_scm_workflow.sh`` script along with a
brief description.

#. Set up the case configuration to run.

   * ``CASE_LIST``: A list of cases to test. Currently supported cases include twpice, MAGIC_LEG12A,
     MAGIC_LEG15A, MOSAiC-AMPS, MOSAiC-SS, COMBLE, and  MPACE_REF.
   * ``SUITE_LIST``: A list of suites to test. This list is also used for configuring the CCPP SCM. Please check all suites under CCPP at https://github.com/NCAR/ccpp-scm/tree/main/ccpp/suites.
   * ``COLUMN_AREAS``: A list of column areas in m^2. If this is left empty, then the cases default
     column area is used.
   * List of time steps and respective inner timesteps (for Thompson and TEMPO) and output frequencies. These arrays must be the
     same length as they are run in sequence with each other rather than running each permutation. For
     example, index 1 of the arrays are one simulation, index 2 are another simulation, etc.
     * ``TIME_STEPS``: A list of model time steps.
     * ``PHYSICS_TIME_STEPS``: A list of physics (inner) time steps.
     * ``OUT_FREQS``: A list of output frequencies.
     * ``DIAG_FREQS``: A list of diagnostic output frequencies.

#. Select system configuration.

   * ``PLATFORM``: Platform to run on. Currently only NOAA's Ursa system has been tested.
   * ``COMPILER``: Compiler to build with. (intel/gnu)

#. Select the CCPP SCM repository to use.

   * ``scm_type``: A flag for the type of CCPP SCM repository to use. (local/github)
   * ``GIT_URL``: The URL of the CCPP SCM github repo you wish to clone. (scm_type must be 'github')
   * ``GIT_BRANCH``: The CCPP SCM github branch you wish to use. (scm_type must be 'github')
   * ``scm_tag``: The name appended to the CCPP SCM top directory (e.g. ccpp-scm-{scm_tag}).
   * ``local_scm_dir``: The path to your local CCPP SCM build (scm_type must be 'local').

#. Toggle options for building and running the CCPP SCM.

   * ``make_build``: Logical switch for selecting whether to build the CCPP SCM or not.
   * ``build_32bit``: Logical switch for building with single precision. Note that only certain physics
    support single precission.
   * ``rerun_cases``: Logical option for rerunning simulations if their output already exists.

#. Select plotting options:

   * ``PLOT_DIR``: Name used for the directory where plots will be created.
   * ``OBS_COMPARE``: Logical option for comparing to observations.

   .. note::
      Not all cases have observations to compare with and will therefore be set to false by default.

#. Options for comparing to a local baseline(s).

   * ``plot_cmp_baseline``: Logical option for whether to compare to a local baseline run. Assumes the
     the simulation(s) for comparison already exist.
   * ``baseline_path``: Path to the baseline output. For more than one baseline comparison, provide as
     a comma-separated list.
   * ``baseline_label``: The label(s) used in the plot legends for the baseline run(s). Provide as a
     comma-separated list, if more than one baseline.

Once the run script is configured, it can be run on the command line. It will automatically submit CCPP SCM
jobs to the queue on Ursa. Before running the script, modify the ``batch_template`` as necessary,
such as the account used to run jobs with, and then execute the ``run_scm_workflow.sh``.

.. code-block:: console

   ./run_scm_workflow.sh

As the workflow runs, it will perform the following steps:

#. If you have ``make_build`` turned on, it will try to build the CCPP SCM, cloning it if necessary. If the
   CCPP SCM executable already exists in the specified directory, then it will prompt whether to rebuild or
   not. The CCPP SCM will be configured and built with the suites in ``SUITE_LIST``.

#. If it does not already exists, the workflow will download the static data necessary for running the
   CCPP SCM and place it in a directory ``scm_workflow/fix_data`` used for all future runs.

#. The workflow will loop through and run all experiments for each case in ``CASE_LIST``. If the case is
   part of the DEPHY repository, it will clone the repository into ``scm_workflow/DEPHY-CCPP SCM``, if it
   does not already exist.

   Jobs are submitted in parallel and plotting will fail if one of the jobs fail for a given case. You may
   execute the workflow a second time if any jobs fail the first time through. Log files for failed jobs
   can be found in CCPP SCM directory ``scm/bin``.

   Once all jobs are complete, the runs will be moved to a common run directory
   ``scm_workflow/scm_runs/${scm_tag}``.

   .. note::
      The workflow will skip any pre-existing runs unless you turn on ``rerun_cases``.

#. For each case, plots listed in ``scripts/plot_config_template.ini`` will be created and placed in a
   directory ``scm_workflow/scm_plots/${PLOT_DIR}``.

#. A java script config file will be created in ``scm_workflow/scm_plots/${PLOT_DIR}`` used for viewing
   the plots via github pages. This config and the plots will need to be manually pushed to github as 
   the workflow does not currently perform this task. Steps to do this are outlined in Section 2.2.

====================================
Github Pages Setup to View the plots
====================================

If it does not already exist, create a new branch off of ``main`` in the scm_workflow.

.. code-block:: console

   git checkout -b gh_pages

Modify ``scm_workflow/scripts/html/index.html`` to add your new run(s) to the main page selection.
Within the <div> class, add a line:

.. code-block:: console

   <a href="viewer.html?config={scm_tag}">{label}</a>

replacing ``{scm_tag}`` with the actual ``scm_tag`` from the ``run_scm_workflow.sh`` and replacing
``{label}`` with the desired title for the main page configuration selection.

Add, commit, and push the ``scm_workflow/scm_plots/${PLOT_DIR}`` and the
``scm_workflow/scripts/html/index.html``.
     
.. code-block:: console

   git add scm_workflow/scm_plots/${PLOT_DIR} scm_workflow/scripts/html/index.html
   git commit -m 'commit message'
   git push origin gh_pages

.. note::
   The paths in ``git add`` should be relative to your current location.

Ensure the ``gh_pages`` branch is setup for deployment. In your GitHub scm_workflow repository, select
the ``settings`` tab, and then navigate to ``Pages`` in the left sidebar. Ensure that the Source is set
to ``Deploy from a branch`` and select the branch to use, e.g. gh_pages.

Open the URL (e.g. \https://{org/fork_name}.github.io/scm_workflow) in you browser to select a
configuration and view the plots.
