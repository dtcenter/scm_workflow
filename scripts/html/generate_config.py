import os
import json

PLOT_ROOT = os.environ.get("plot_path")

# Load figure template
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
template_path = os.path.join(SCRIPT_DIR, "config_template.json")

with open(template_path) as f:
    figures_template = json.load(f)

# Determine unique case names
#case_names = set()

#for d in os.listdir(PLOT_ROOT):
#    full_path = os.path.join(PLOT_ROOT, d)
#    if not os.path.isdir(full_path):
#        continue
#
#    if d == "comp":
#        continue
#
#    case_name = d.split("_")[0]
#    case_names.add(case_name)



# Build config for each case
#for case_name in sorted(case_names):
cases = {}
suites = {}
areas = {}
dts = {}
dtis = {}

# Loop through directories in scm_plots/plots_test
for d in sorted(os.listdir(PLOT_ROOT)):
    full_path = os.path.join(PLOT_ROOT, d)

    if not os.path.isdir(full_path):
        continue

    if d == "comp":
        suites["comp"] = {"label": "Comparison"}
        continue

    if "_SCM_" not in d or "_area" not in d:
        continue

    case_name = d.split("_SCM", 1)[0]
    cases[case_name] = {"label": case_name}
    suite = d.split("_SCM_", 1)[1].split("_area", 1)[0]
    suites[suite] = {"label": suite}
    area = d.split("_area", 1)[1].split("_dt", 1)[0]
    areas[area] = {"label": area}
    dt = d.split("_dt", 1)[1].split("_dti", 1)[0]
    dts[dt] = {"label": dt}
    dti = d.split("_dti", 1)[1]
    dtis[dti] = {"label": dti}

config = {
    "base_plot_dir": PLOT_ROOT,
    "cases": cases,
    "suites": suites,
    "areas": areas,
    "dts": dts,
    "dtis": dtis,
    "figures": figures_template
}

config_path = os.path.join(PLOT_ROOT,"config.json")

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print("Generated config.json")
