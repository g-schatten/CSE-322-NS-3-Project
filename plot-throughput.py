"""
plot-throughput.py
Reads tput20.dat  → Fig. 8  (20% BDP buffer)
Reads tput200.dat → Fig. 9  (200% BDP buffer)

Output format from simulation:
  flow_id  time_s  throughput_Mbps
  1 = CUBIC-1,  2 = CUBIC-2,  3 = TCP-1,  4 = TCP-2
"""

import collections
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ── Style ──────────────────────────────────────────────────────────
STYLES = {
    1: dict(color="red",     linestyle="-",  linewidth=1.2, label="CUBIC-1"),
    2: dict(color="green",   linestyle="-",  linewidth=1.2, label="CUBIC-2"),
    3: dict(color="blue",    linestyle="--", linewidth=0.9, label="TCP (Reno)-1"),
    4: dict(color="magenta", linestyle="--", linewidth=0.9, label="TCP (Reno)-2"),
}

# Warm-up period to exclude (slow-start transient)
WARMUP_S = 15.0

# Moving average window for smoothing (seconds)
SMOOTH_WINDOW_S = 3.0


def load_tput(path):
    """Return dict: flow_id → (list of times, list of throughputs in Mbps)."""
    flows = collections.defaultdict(lambda: ([], []))
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split()
                if len(parts) < 3:
                    continue
                fid, t, tput = int(parts[0]), float(parts[1]), float(parts[2])
                flows[fid][0].append(t)
                flows[fid][1].append(tput)
    except FileNotFoundError:
        print(f"Warning: {path} not found", file=sys.stderr)
    return flows


def smooth_data(times, tputs, window_s):
    """Apply moving average smoothing with given window size (seconds)."""
    if len(times) < 2:
        return times, tputs

    # Infer sampling interval
    times_arr = np.array(times)
    diffs = np.diff(times_arr[:min(20, len(times_arr))])
    samp_int = float(np.median(diffs))

    window_pts = max(2, int(window_s / samp_int))

    # Apply moving average
    tputs_arr = np.array(tputs)
    kernel = np.ones(window_pts) / window_pts
    tputs_smooth = np.convolve(tputs_arr, kernel, mode='same')

    return times, tputs_smooth


def make_figure(flows, buf_label, buf_pct, out_file):
    fig, ax = plt.subplots(figsize=(8, 4))

    for fid, (times_raw, tputs_raw) in sorted(flows.items()):
        # Filter warm-up
        data = [(t, tp) for t, tp in zip(times_raw, tputs_raw) if t >= WARMUP_S]
        if not data:
            continue

        times, tputs = zip(*data)
        times, tputs = list(times), list(tputs)

        # Apply smoothing
        times_smooth, tputs_smooth = smooth_data(times, tputs, SMOOTH_WINDOW_S)

        ax.plot(times_smooth, tputs_smooth, **STYLES[fid])

    ax.set_xlabel("Time (s)", fontsize=11)
    ax.set_ylabel("Throughput (Mbps)", fontsize=11)
    ax.set_title(
        f"Throughput vs Time — {buf_label} BDP buffer ({buf_pct}%)\n"
        f"[500 Mbps, RTT = 100 ms, 2 CUBIC + 2 TCP (Reno), {SMOOTH_WINDOW_S}s moving avg]",
        fontsize=10,
    )
    ax.legend(loc="upper right", fontsize=9)
    ax.set_ylim(bottom=0)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_file, dpi=150)
    print(f"Saved {out_file}")
    plt.close(fig)


# ── Main ──────────────────────────────────────────────────────────
flows20  = load_tput("tput20.dat")
flows200 = load_tput("tput200.dat")

make_figure(flows20,  "Small (20%)",  20,  "fig8-tput-20pct.png")
make_figure(flows200, "Large (200%)", 200, "fig9-tput-200pct.png")
