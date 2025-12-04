import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

COMPARISON = 4.5
SIZE = (7, 5)
SIZE_RATION = SIZE[1] / COMPARISON

# ------------ PARAMETERS ------------
FILE = "results/requests_trace.txt"
discard_first_n = 0
z_value = 3   # 99.7% (3*std) CI z-score
# -------------------------------------

# Load data
df = pd.read_csv(
    FILE,
    header=None,
    names=["experiment", "test_id", "start_start", "start_end", "finish_start", "finish_end"]
)

# Compute durations in seconds
df["startup"] = (df["start_end"] - df["start_start"]) / 1000.0
df["finishing"] = (df["finish_end"] - df["finish_start"]) / 1000.0

# Remove first 50 cycles
df = df[df["test_id"] > discard_first_n]

# Name mapping
label_map = {
    "baseline": "Baseline",
    "enforcer-simple": "Simple\nWorkflow",
    "enforcer-complex": "Complex\nWorkflow"
}
df["experiment_label"] = df["experiment"].map(label_map)

# CI-based outlier removal
cleaned = []

for exp, group in df.groupby("experiment_label"):

    # Startup filtering
    mu_s = group["startup"].mean()
    sd_s = group["startup"].std()
    low_s = mu_s - z_value * sd_s
    high_s = mu_s + z_value * sd_s

    # Finishing filtering
    mu_f = group["finishing"].mean()
    sd_f = group["finishing"].std()
    low_f = mu_f - z_value * sd_f
    high_f = mu_f + z_value * sd_f

    # Keep values within CI for BOTH metrics
    filtered = group[
        (group["startup"].between(low_s, high_s)) &
        (group["finishing"].between(low_f, high_f))
    ]

    cleaned.append(filtered)

df_clean = pd.concat(cleaned)

# Final means & stds
summary = df_clean.groupby("experiment_label")[["startup", "finishing"]].agg(["mean", "std"])
print("\n===== FINAL RESULTS AFTER OUTLIER REMOVAL =====\n")
print(summary)
print("\n(Mean ± Std) values are in seconds.\n")

present_labels = sorted(df_clean["experiment_label"].unique(),
                        key=lambda x: list(label_map.values()).index(x))


# ----- BOXPLOTS -----
plt.figure(figsize=(10, 6))
ax = sns.boxplot(data=df_clean, x="experiment_label", y="startup", order=present_labels)
ax.yaxis.label.set_fontsize(15 * SIZE_RATION)
ax.xaxis.label.set_fontsize(15 * SIZE_RATION)
ax.tick_params(labelsize=12 * SIZE_RATION)
plt.ylabel("Time (s)")
plt.xlabel("")
plt.tight_layout()
plt.savefig(f"resources_startup.pdf")
plt.show()

plt.figure(figsize=(10, 6))
ax = sns.boxplot(data=df_clean, x="experiment_label", y="finishing")
ax.yaxis.label.set_fontsize(15 * SIZE_RATION)
ax.xaxis.label.set_fontsize(15 * SIZE_RATION)
ax.tick_params(labelsize=12 * SIZE_RATION)
plt.ylabel("Time (s)")
plt.tight_layout()
plt.savefig(f"resources_finish.pdf")
plt.show()
