import os
import re
from typing import Literal
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

COMPARISON = 6.5
SIZE: tuple[Literal[5], Literal[1]] = (10, 4.1)
SIZE_RATION = SIZE[0] / COMPARISON

BASE_DIR = "results"

# Regex for function extraction: pod_{name}-{5digits}-deployment...
FUNC_RE = re.compile(r"pod_([a-zA-Z0-9\-]+)-\d{5}-deployment")

# Regex to extract latency: "latency": "0.053133726s"
LAT_RE = re.compile(r'"latency":\s*"([0-9.]+)s"')

EXPECTED_ENTRIES = 350


def extract_function_name(filename):
    m = FUNC_RE.search(filename)
    if not m:
        return None
    return m.group(1)


def extract_latencies_from_file(filepath):
    latencies = []
    with open(filepath, "r") as f:
        for line in f:
            match = LAT_RE.search(line)
            if match:
                latencies.append(float(match.group(1)) * 1000)  # milliseconds
    return latencies


records = []

###############################################
# WALK ALL DIRECTORIES IN results/*
###############################################
for root, dirs, files in os.walk(BASE_DIR):
    for file in files:
        if not file.endswith("queue_proxy_logs.txt"):
            continue

        filepath = os.path.join(root, file)

        # Determine experiment info from folder name
        # e.g., test-baseline_namespace-refund_20250214-195626
        folder = os.path.basename(root)

        # Extract "baseline" or "enforce"
        if "test-baseline" in folder:
            mode = "baseline"
        elif "test-enforce" in folder:
            mode = "enforce"
        else:
            continue  # unknown folder, skip

        # Extract application (refund or valve)
        if "_namespace-refund_" in folder:
            app = "refund"
        elif "_namespace-valve_" in folder:
            app = "valve"
        elif "_namespace-long-parallel_" in folder:
            app = "long-parallel"
        elif "_namespace-long-sequence_" in folder:
            app = "long-sequence"
        else:
            continue

        # Extract function name
        func = extract_function_name(file)
        if not func or func == "workflow" or func == "entry-point" or (app == "valve" and (func == "f2" or func == "f3")) or func == "database-dummy":
            continue

        # Extract latencies
        latencies = extract_latencies_from_file(filepath)

        # Validate count
        if len(latencies) != EXPECTED_ENTRIES and func != "database-dummy" and (
            app == "valve" and (func != "f2" and func != "f3")
        ):
            raise ValueError(
                f"File {filepath} has {len(latencies)} entries, expected {EXPECTED_ENTRIES}"
            )

        # Store record
        records.append({
            "app": app,
            "function": func,
            "mode": mode,
            "latencies": latencies,
            "mean": pd.Series(latencies).mean(),
            "std": pd.Series(latencies).std()
        })

###############################################
# BUILD DATAFRAME
###############################################
df = pd.DataFrame(records)
order = [*["f" + str(i) for i in range(1, 141)], "database-dummy", "result"]
df["function"] = pd.Categorical(df["function"], categories=order, ordered=True)
df = df.sort_values("function")

print("\n==== SUMMARY OF LOADED LATENCY DATA ====\n")
print(df[["app", "function", "mode", "mean", "std"]])

###############################################
# PLOTS PER APPLICATION
###############################################
sns.set(style="whitegrid")

for app in ["refund", "valve"]:
    df_app = df[df["app"] == app].copy()

    if df_app.empty:
        continue

    # Pivot for bar plot: rows=function, columns=mode
    print(df_app)
    pivot_mean = df_app.pivot(index="function", columns="mode", values="mean")
    pivot_std = df_app.pivot(index="function", columns="mode", values="std")
    pivot_mean.columns.name = "Mode"
    pivot_std.columns.name = "Mode"

    # Sort functions alphabetically
    pivot_mean = pivot_mean.sort_index()
    pivot_std = pivot_std.loc[pivot_mean.index]

    # Plot
    ax = pivot_mean.plot.bar(
        yerr=pivot_std,
        figsize=SIZE,
        capsize=5,
        rot=0,
        color=sns.color_palette("colorblind")
        # title=f"Latency Comparison for {app.capitalize()} Application",
    )
    ax.set_ylabel("Average Latency\n(ms)")
    ax.set_xlabel("Function")

    ax.yaxis.label.set_fontsize(15 * SIZE_RATION)
    ax.xaxis.label.set_fontsize(15 * SIZE_RATION)
    ax.tick_params(labelsize=12 * SIZE_RATION)
    ax.legend(fontsize=12 * SIZE_RATION,
        title_fontsize=12 * SIZE_RATION,
        title="Mode",
        loc="lower right",)
    ax.yaxis.set_label_coords(-.05, 0.43)

    plt.tight_layout()
    plt.savefig(f"{app}.pdf", bbox_inches='tight', pad_inches=0)
    plt.show()

###############################################
# difference POINT-PLOTS WITH LINEAR FIT
# for long-sequence and long-parallel
###############################################
for app in ["long-sequence", "long-parallel"]:

    df_app = df[df["app"] == app].copy()
    if df_app.empty:
        continue

    baseline_df = df_app[df_app["mode"] == "baseline"].set_index("function")
    enforce_df  = df_app[df_app["mode"] == "enforce"].set_index("function")

    common_funcs = baseline_df.index.intersection(enforce_df.index)

    difference_records = []

    for func in common_funcs:
        base_lat = baseline_df.loc[func]["latencies"]
        enf_lat  = enforce_df.loc[func]["latencies"]

        differences = [e - b for e, b in zip(enf_lat, base_lat)]

        difference_records.append({
            "function": func,
            "mean_difference": np.mean(differences),
            "difference": differences  # keep raw values → pointplot will compute mean & sd
        })

    # Expand so seaborn can compute stats
    expanded = []
    for r in difference_records:
        for value in r["difference"]:
            expanded.append({
                "function": r["function"],
                "difference": value
            })

    difference_df = pd.DataFrame(expanded)

    # Ensure proper ordering
    difference_df["function"] = pd.Categorical(
        difference_df["function"],
        categories=order,
        ordered=True
    )
    difference_df = difference_df.sort_values("function")

    # Numeric x positions
    funcs = difference_df["function"].unique()
    x_numeric = np.arange(len(funcs))

    # ---- PLOT USING sns.pointplot ----
    plt.figure(figsize=SIZE)

    ax = sns.pointplot(
        data=difference_df,
        x="function",
        y="difference",
        errorbar=("sd"),   # use standard deviation
        join=False,        # points only, no connecting line
        color=sns.color_palette("colorblind")[0],
        label="Mean difference ± std",
        capsize=.4
    )

    # ---- ADD BEST-FIT LINE ----
    # Compute mean per function for fitting
    # Extract arrays for fitting
    funcs = set(difference_df["function"])

    x_arr = pd.array(list(range(len(funcs))))
    y_arr = pd.DataFrame(difference_records)["mean_difference"].values

    # Best-fit linear regression (y = ax + b)
    a, b = np.polyfit(x_arr, y_arr, 1)
    x_fit = np.linspace(x_arr.min(), x_arr.max(), 200)
    y_fit = a * x_fit + b

    sns.lineplot(
        x=x_fit,
        y=y_fit,
        color=sns.color_palette("colorblind")[1],
        linewidth=2,
        label=f"y = {a:.4f}x + {b:.4f}"
    )

    # Reference line at 0 (difference baseline)
    plt.axhline(0, color="red", linestyle="--", linewidth=1)

    # Fix axis limits
    plt.xlim(-0.5, len(funcs) - 0.5)
    plt.ylim(0, )
    plt.xticks([i for i in x_arr if not (i + 1)%10])

    plt.xticks(rotation=45)
    plt.xlabel("Function")
    plt.ylabel("Latency Difference\n(ms)")

    ax.yaxis.label.set_fontsize(15 * SIZE_RATION)
    ax.xaxis.label.set_fontsize(15 * SIZE_RATION)
    ax.tick_params(labelsize=12 * SIZE_RATION)
    ax.yaxis.set_label_coords(-.05, 0.43)

    plt.tight_layout()
    plt.legend(fontsize=12 * SIZE_RATION)
    plt.savefig(f"{app}.pdf", bbox_inches='tight', pad_inches=0)
    plt.show()

    print(f"\n=== difference Summary (difference) for {app} ===\n")
    print(difference_df.groupby("function")["difference"].agg(["mean", "std"]))


# ###############################################
# # difference POINT-PLOT WITH LOG SCALE FOR long-parallel
# ###############################################
# import numpy as np

# app = "long-parallel"
# df_app = df[df["app"] == app].copy()

# if not df_app.empty:

#     baseline_df = df_app[df_app["mode"] == "baseline"].set_index("function")
#     enforce_df  = df_app[df_app["mode"] == "enforce"].set_index("function")

#     common_funcs = baseline_df.index.intersection(enforce_df.index)

#     difference_records = []

#     for func in common_funcs:
#         base_lat = baseline_df.loc[func]["latencies"]
#         enf_lat  = enforce_df.loc[func]["latencies"]

#         differences = [e / b for e, b in zip(enf_lat, base_lat)]

#         difference_records.append({
#             "function": func,
#             "mean_difference": np.mean(differences),
#             "std_difference": np.std(differences),
#         })

#     difference_df = pd.DataFrame(difference_records)

#     funcs = list(difference_df["function"])
#     x = np.arange(len(funcs))
#     means = difference_df["mean_difference"].values
#     stds  = difference_df["std_difference"].values

#     # ---- LOG-SPACE fit ----
#     log_means = np.log(means)
#     a, b = np.polyfit(x, log_means, 1)        # fit: log(y) = ax + b

#     # log-linear model: y = exp(ax + b)
#     x_fit = np.linspace(x.min(), x.max(), 200)
#     y_fit = np.exp(a * x_fit + b)

#     # ---- PLOT ----
#     plt.figure(figsize=(12, 6))

#     # error bars still in linear scale (correct approach)
#     plt.errorbar(
#         x,
#         means,
#         yerr=stds,
#         fmt='o',
#         capsize=5,
#         markersize=6,
#         linestyle="none",
#         color="blue",
#         ecolor="black",
#         label="Mean difference ± std"
#     )

#     # Regression curve in log space
#     plt.plot(
#         x_fit,
#         y_fit,
#         color="green",
#         linewidth=2,
#         label=f"log-fit: log(y) = {a:.4f}x + {b:.4f}"
#     )

#     # Reference line at difference=1
#     plt.axhline(1.0, color="red", linestyle="--", linewidth=1)

#     # Tight x-boundaries (fix spare space)
#     plt.xlim(-0.5, len(funcs) - 0.5)

#     plt.yscale("log")     # <<< ✔ KEY CHANGE: LOG SCALE

#     plt.xticks(x, funcs, rotation=45)
#     plt.ylabel("Latency difference (enforce / baseline) — LOG SCALE")
#     plt.xlabel("Function")
#     plt.title("Enforce / Baseline Latency difference (Logarithmic Fit) — Long Parallel")

#     plt.legend()
#     plt.tight_layout()
#     plt.show()

#     print("\n=== difference Summary — LOG SCALE FIT (long-parallel) ===\n")
#     print(difference_df)
