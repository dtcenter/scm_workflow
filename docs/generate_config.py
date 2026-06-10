import os
import json

PLOT_ROOT = os.environ.get("plot_path")
PLOT_DIRNAME = os.environ.get("PLOT_DIR")

# Load figure template
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
template_path = os.path.join(SCRIPT_DIR, "config_template.json")

with open(template_path) as f:
    figures_template = json.load(f)

# Determine unique case names
cases = {}
case_names = set()
for d in os.listdir(PLOT_ROOT):
    full_path = os.path.join(PLOT_ROOT, d)
    if not os.path.isdir(full_path):
        continue
    if "_SCM_" in d:
        case_names.add(d.split("_SCM_", 1)[0])

# Build config for each case
for case_name in sorted(case_names):
    suites = {}
    areas = {}
    timesteps = {}

    # Loop through directories in scm_plots/plots_test
    for d in sorted(os.listdir(PLOT_ROOT)):

        full_path = os.path.join(PLOT_ROOT, d)
        if not os.path.isdir(full_path):
            continue

        if d == f"{case_name}_comp":
            suites["comp"] = {"label": "Comparison"}
            continue

        if not d.startswith(f"{case_name}_SCM_"):
            continue

        suite = d.split("_SCM_", 1)[1].split("_area", 1)[0]
        suites[suite] = {"label": suite}
        area = d.split("_area", 1)[1].split("_dt", 1)[0]
        areas[area] = {"label": area}
        dt = d.split("_dt", 1)[1].split("_dti", 1)[0]
        dti = d.split("_dti", 1)[1]

        dt_dti = f"{dt}_{dti}"
        label = f"{dt}s / {dti}s"

        timesteps[dt_dti] = {"label": label}

    cases[case_name] = {
        "label": case_name,
        "suites": suites,
        "areas": areas,
        "timesteps": timesteps,
        "figures": figures_template
    }

config = {
    "base_plot_dir": f"../scm_plots/{PLOT_DIRNAME}",
    "cases": cases
}

config_path = os.path.join(PLOT_ROOT,"config.json")

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print("Generated config.json")
