#!/usr/bin/env python3
"""
Generates Fig. 3 and Fig. 4 from the CUBIC paper:
  "CUBIC: A New TCP-Friendly High-Speed TCP Variant" – Rhee & Xu

cwnd.dat format (3 columns):
    flow_id   time_s   cwnd_bytes
    1,2 = CUBIC flows
    3,4 = TCP SACK flows

Fig. 3: 100 – 200 s  (CUBIC-2 just started at 100 s; CUBIC-1 at high W_max)
Fig. 4: 0   – 300 s  (full run; convergence visible at ~220 s)
"""

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

SEG = 1448   # bytes per segment (must match simulation)

# ── Parse cwnd.dat ────────────────────────────────────────────────────────────
flows = {1: ([], []), 2: ([], []), 3: ([], []), 4: ([], [])}

with open("cwnd.dat") as f:
    for line in f:
        parts = line.split()
        if len(parts) != 3:
            continue
        fid, t, c = int(parts[0]), float(parts[1]), float(parts[2])
        if fid not in flows:
            continue
        flows[fid][0].append(t)
        flows[fid][1].append(c / SEG)          # convert bytes → packets

# Convert to numpy arrays
for fid in flows:
    flows[fid] = (np.array(flows[fid][0]), np.array(flows[fid][1]))

# ── Style matching the paper ──────────────────────────────────────────────────
STYLES = {
    1: dict(color="red",     linestyle="-",  linewidth=1.2, label="CUBIC-1"),
    2: dict(color="green",   linestyle="-",  linewidth=1.2, label="CUBIC-2"),
    3: dict(color="blue",    linestyle="-",  linewidth=0.9, label="TCP-1"),
    4: dict(color="magenta", linestyle="-",  linewidth=0.9, label="TCP-2"),
}

TITLE = ("CUBIC window curve\n"
         "[50 Mbps, RTT = 100 ms, C = 0.4, β = 0.8]")


def plot_window(ax, t_start, t_end):
    for fid, (times, cwnds) in flows.items():
        mask = (times >= t_start) & (times <= t_end)
        if mask.sum() == 0:
            continue
        ax.plot(times[mask], cwnds[mask], **STYLES[fid])
    ax.set_xlim(t_start, t_end)
    ax.set_xlabel("Time (second)", fontsize=12)
    ax.set_ylabel("CWND (packets)", fontsize=12)
    ax.set_title(TITLE, fontsize=12)
    ax.legend(fontsize=10, loc="upper right")
    ax.grid(True, linestyle="--", alpha=0.35)
    ax.yaxis.set_major_locator(ticker.AutoLocator())


# ── Fig. 3: 20 – 40 s (20-second window) ─────────────────────────────────────
# CUBIC-2 just joined at t=20 s.  CUBIC-1 has been running for 20 s and holds
# a high W_max.  This 20-second slice shows CUBIC-1 at its plateau and CUBIC-2
# growing from zero — mirroring the paper's Fig. 3 convergence setup.
fig3, ax3 = plt.subplots(figsize=(10, 5))
plot_window(ax3, 20, 40)
fig3.tight_layout()
fig3.savefig("fig3-cubic-window.png", dpi=150)
print("Saved fig3-cubic-window.png")

# ── Fig. 4: 0 – 60 s (60-second window) ──────────────────────────────────────
# Full 60-second run: CUBIC-1 alone for first 20 s, CUBIC-2 joins and both
# converge toward equal share — mirroring the paper's Fig. 4 fairness story.
fig4, ax4 = plt.subplots(figsize=(12, 5))
plot_window(ax4, 0, 60)
fig4.tight_layout()
fig4.savefig("fig4-cubic-fairness.png", dpi=150)
print("Saved fig4-cubic-fairness.png")

# ── Statistics ────────────────────────────────────────────────────────────────
print("\n--- Per-flow statistics (full 90 s run) ---")
for fid, (times, cwnds) in flows.items():
    if len(times) == 0:
        print(f"Flow {fid}: no data")
        continue
    kind = "CUBIC" if fid <= 2 else "TCP  "
    drops = int(np.sum(np.diff(cwnds) < 0)) if len(cwnds) > 1 else 0
    print(f"Flow {fid} ({kind})  "
          f"mean={cwnds.mean():.1f} pkts  "
          f"max={cwnds.max():.1f} pkts  "
          f"reductions={drops}")
