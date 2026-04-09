"""
plot-cov.py
Reads cov20.dat  → Fig. 10  (CoV of throughput, 20% BDP buffer)
Reads cov200.dat → Fig. 11  (CoV of throughput, 200% BDP buffer)

CoV method (paper §V):
  For time scale τ seconds:
    1. Group per-interval throughput samples into non-overlapping windows of τ s
    2. Compute the mean throughput in each window
    3. CoV(τ) = std(window_means) / mean(window_means)
  A lower CoV means more stable throughput at that time scale.

Data format (from test-cubic-cov):
  flow_id  time_s  throughput_Mbps   (one row per 0.5 s per flow)
  1 = CUBIC-1,  2 = CUBIC-2,  3 = TCP-1,  4 = TCP-2
"""

import collections
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ── Style ─────────────────────────────────────────────────────────────
STYLES = {
    1: dict(color="red",     linestyle="-",  linewidth=1.4,
            marker="o", markersize=4, label="CUBIC-1"),
    2: dict(color="green",   linestyle="-",  linewidth=1.4,
            marker="s", markersize=4, label="CUBIC-2"),
    3: dict(color="blue",    linestyle="--", linewidth=1.0,
            marker="^", markersize=4, label="TCP (Reno)-1"),
    4: dict(color="magenta", linestyle="--", linewidth=1.0,
            marker="v", markersize=4, label="TCP (Reno)-2"),
}

# Time-window sizes to evaluate CoV at (in seconds).
# Limited to windows where at least 5 non-overlapping windows fit in the data.
WINDOW_SIZES = [1, 2, 3, 5, 7, 10, 15, 20]

# Warm-up period to exclude (slow-start phase)
WARMUP_S = 10.0


def load_data(path):
    """Return dict: flow_id → sorted list of (time, tput_Mbps)."""
    flows = collections.defaultdict(list)
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split()
                if len(parts) < 3:
                    continue
                fid  = int(parts[0])
                t    = float(parts[1])
                tput = float(parts[2])
                flows[fid].append((t, tput))
    except FileNotFoundError:
        print(f"Warning: {path} not found — skipping.", file=sys.stderr)
    for fid in flows:
        flows[fid].sort()
    return dict(flows)


def compute_cov(times_tputs, window_s, samp_interval):
    """
    Compute CoV for a given window size.
    times_tputs: list of (time, tput) already sorted, after warm-up removed.
    Returns CoV or None if not enough data.
    """
    tputs = [tp for _, tp in times_tputs]
    samples_per_window = max(1, round(window_s / samp_interval))

    # Build non-overlapping window means
    window_means = []
    for start in range(0, len(tputs) - samples_per_window + 1, samples_per_window):
        chunk = tputs[start : start + samples_per_window]
        window_means.append(np.mean(chunk))

    if len(window_means) < 3:
        return None  # too few windows for a meaningful CoV

    mean_val = np.mean(window_means)
    if mean_val < 1e-9:
        return None  # flow produced no traffic

    return np.std(window_means, ddof=1) / mean_val


def infer_samp_interval(times_tputs):
    """Infer sampling interval from the data."""
    times = [t for t, _ in times_tputs]
    if len(times) < 2:
        return 1.0
    diffs = [times[i + 1] - times[i] for i in range(min(20, len(times) - 1))]
    return float(np.median(diffs))


def make_cov_figure(flows, buf_label, buf_pct, out_file):
    fig, ax = plt.subplots(figsize=(8, 4))

    any_data = False
    for fid, raw in sorted(flows.items()):
        # Remove warm-up period
        data = [(t, tp) for t, tp in raw if t >= WARMUP_S]
        if not data:
            continue

        samp_int = infer_samp_interval(data)

        xs, ys = [], []
        for w in WINDOW_SIZES:
            cov = compute_cov(data, w, samp_int)
            if cov is not None:
                xs.append(w)
                ys.append(cov)

        if xs:
            ax.plot(xs, ys, **STYLES[fid])
            any_data = True

    if not any_data:
        ax.text(0.5, 0.5, "No data\n(run the simulation first)",
                ha="center", va="center", transform=ax.transAxes, fontsize=12)

    ax.set_xlabel("Time scale (s)", fontsize=11)
    ax.set_ylabel("Coefficient of Variation (CoV)", fontsize=11)
    ax.set_title(
        f"Stability: CoV of Throughput — {buf_label} BDP buffer ({buf_pct}%)\n"
        "[500 Mbps, RTT = 100 ms, 2 CUBIC + 2 TCP (Reno)]",
        fontsize=10,
    )
    ax.legend(loc="upper right", fontsize=9)
    ax.set_ylim(bottom=0)
    ax.set_xlim(left=0)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_file, dpi=150)
    print(f"Saved {out_file}")
    plt.close(fig)


# ── Main ──────────────────────────────────────────────────────────────
flows20  = load_data("cov20.dat")
flows200 = load_data("cov200.dat")

make_cov_figure(flows20,  "Small (20%)",  20,  "fig10-cov-20pct.png")
make_cov_figure(flows200, "Large (200%)", 200, "fig11-cov-200pct.png")
