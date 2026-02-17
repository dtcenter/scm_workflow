import os
import json

PLOT_ROOT = "${plot_path}"

CASE_NAME = "${scm_case}"

# Load figure template
with open("config_template.json") as f:
    figures_template = json.load(f)

case_dir = os.path.join(PLOT_ROOT)

suites = {}
areas = {}

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

        # Extract configs
        suite = "_".join(parts[3:-3])
        suites[d] = {"label": suite}
        area = parts[-2]
        areas[d] = {"label": area}

config = {
    "base_plot_dir": PLOT_ROOT,
    "cases": {
        "case": {
            "label": CASE_NAME,
            "suites": suites,
            "figures": figures_template
        }
    }
}

config_path = os.path.join(plot_path,"config.json")
with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print("Generated config.json")
