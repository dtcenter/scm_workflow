import os
import json

PLOT_ROOT = os.environ.get("plot_path")

CASE_NAME = os.environ.get("scm_case") 

# Load figure template
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
template_path = os.path.join(SCRIPT_DIR, "config_template.json")

with open(template_path) as f:
    figures_template = json.load(f)

case_dir = os.path.join(PLOT_ROOT)

suites = {}
areas = {}
dts = {}
dtis = {}

# Loop through directories in scm_plots/plots_test
for d in sorted(os.listdir(case_dir)):
    full_path = os.path.join(case_dir, d)

    if not os.path.isdir(full_path):
        continue

    # Skip non-case dirs except comp
    if CASE_NAME not in d and d != "comp":
        continue

    if d == "comp":
        suites[d] = {"label": "Comparison"}
    else:
        # Extract suite label dynamically
        # Example:
        # MAGIC_LEG15A_SCM_GFS_v16_area12.04km_dt300s_dti150s
        parts = d.split("_")
        print(parts)

        # Extract configs
        suite = "_".join(parts[3:-3])
        suites[suite] = {"label": suite}
        area = parts[-3].replace("area", "", 1)
        areas[area] = {"label": area}
        dt = parts[-2].replace("dt", "", 1)
        dts[dt] = {"label": dt}
        dti = parts[-1].replace("dti", "", 1)
        dtis[dti] = {"label": dti}

print(suites)
config = {
    "base_plot_dir": PLOT_ROOT,
    "cases": {
        "case": {
            "label": CASE_NAME,
            "suites": suites,
            "areas": areas,
            "dts": dts,
            "dtis": dtis,
            "figures": figures_template
        }
    }
}

config_path = os.path.join(PLOT_ROOT,"config.json")
with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print("Generated config.json")
