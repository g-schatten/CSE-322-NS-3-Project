"""
plot-ratio.py
Reads ratio_${link}mbps_${rtt}ms.dat files → Fig. 5 and Fig. 6

Fig. 5: TCP/CUBIC Throughput Ratio (%) vs Link Speed — Short RTT (20 ms)
Fig. 6: TCP/CUBIC Throughput Ratio (%) vs Link Speed — Long  RTT (100 ms)

Ratio = mean_TCP_tput / mean_CUBIC_tput × 100
  100 % → CUBIC is perfectly TCP-friendly (equal share)
  <100 % → CUBIC is more aggressive than TCP
  >100 % → TCP takes more than CUBIC

Data file format (one row per second per flow):
  flow_id  time_s  throughput_Mbps
  flow 1 = CUBIC,  flow 2 = TCP-Reno

Usage:
  .venv/bin/python3 plot-ratio.py
"""

import os
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ── Configuration ─────────────────────────────────────────────────────
LINK_SPEEDS = [20, 100, 300, 500, 1000]   # Mbps, x-axis
RTT_SHORT   = 20                           # ms
RTT_LONG    = 100                          # ms

# Seconds to skip at the start before measuring (slow-start + transient)
WARMUP_S = 15.0


def load_ratio(link_mbps, rtt_ms):
    """
    Load a ratio dat file and return (cubic_mean_Mbps, tcp_mean_Mbps) averaged
    over the steady-state period (after WARMUP_S).
    Returns (None, None) if the file doesn't exist or has no usable data.
    """
    fname = f"ratio_{link_mbps}mbps_{rtt_ms}ms.dat"
    if not os.path.exists(fname):
        print(f"  Missing: {fname}", file=sys.stderr)
        return None, None

    cubic_tputs = []
    tcp_tputs   = []
    with open(fname) as f:
        for line in f:
            parts = line.split()
            if len(parts) < 3:
                continue
            fid  = int(parts[0])
            t    = float(parts[1])
            tput = float(parts[2])
            if t < WARMUP_S:
                continue
            if fid == 1:
                cubic_tputs.append(tput)
            elif fid == 2:
                tcp_tputs.append(tput)

    if not cubic_tputs or not tcp_tputs:
        print(f"  No steady-state data in {fname}", file=sys.stderr)
        return None, None

    return float(np.mean(cubic_tputs)), float(np.mean(tcp_tputs))


def compute_series(rtt_ms):
    """
    For each link speed, compute TCP/CUBIC ratio (%).
    Returns (speeds, ratios) — only includes speeds where data is available.
    """
    speeds = []
    ratios = []
    for link in LINK_SPEEDS:
        cubic_mean, tcp_mean = load_ratio(link, rtt_ms)
        if cubic_mean is None or cubic_mean < 0.01:
            continue
        ratio = tcp_mean / cubic_mean * 100.0
        speeds.append(link)
        ratios.append(ratio)
        print(f"  {link:5d} Mbps, RTT={rtt_ms:3d} ms: "
              f"CUBIC={cubic_mean:.2f} Mbps, TCP={tcp_mean:.2f} Mbps, "
              f"Ratio={ratio:.1f}%")
    return speeds, ratios


def make_figure(rtt_ms, label, out_file):
    fig, ax = plt.subplots(figsize=(7, 4))

    speeds, ratios = compute_series(rtt_ms)

    if speeds:
        ax.plot(speeds, ratios,
                color="red", linestyle="-", linewidth=1.5,
                marker="o", markersize=6, label="CUBIC")
    else:
        ax.text(0.5, 0.5, "No data\n(run the simulations first)",
                ha="center", va="center", transform=ax.transAxes, fontsize=12)

    # Reference line: 100% = perfectly TCP-friendly
    ax.axhline(100, color="gray", linestyle="--", linewidth=1.0,
               label="100% (TCP-friendly)")

    ax.set_xlabel("Link Speed (Mbps)", fontsize=11)
    ax.set_ylabel("TCP / CUBIC Throughput Ratio (%)", fontsize=11)
    ax.set_title(
        f"TCP-Friendly Ratio — {label}\n"
        "[RTT = " + str(rtt_ms) + " ms, 1 CUBIC + 1 TCP (Reno), RED+ECN queue]",
        fontsize=10,
    )
    ax.set_xscale("log")
    ax.set_xticks(LINK_SPEEDS)
    ax.get_xaxis().set_major_formatter(matplotlib.ticker.ScalarFormatter())
    ax.set_ylim(0, 200)
    ax.legend(fontsize=9)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_file, dpi=150)
    print(f"Saved {out_file}")
    plt.close(fig)


import matplotlib.ticker

print("Fig 5 — Short RTT:")
make_figure(RTT_SHORT, f"Short RTT ({RTT_SHORT} ms)", "fig5-ratio-short-rtt.png")

print("\nFig 6 — Long RTT:")
make_figure(RTT_LONG,  f"Long RTT ({RTT_LONG} ms)",   "fig6-ratio-long-rtt.png")
