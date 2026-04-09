#!/usr/bin/env python3
"""
plot-rtt-comparison.py
Compares Original CUBIC vs RTT-Trend-Aware CUBIC

Input: comparison.dat
  Format: flow_id  time_s  cwnd_bytes  rtt_ms  gamma
  flow 1, 2 = Original CUBIC
  flow 3, 4 = RTT-Aware CUBIC

Output:
  - comparison-cwnd-single.png    (1 Original vs 1 RTT-Aware)
  - comparison-cwnd-all.png       (All 4 flows)
  - comparison-rtt-gamma.png      (RTT and Gamma evolution for RTT-Aware)
"""

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np
import sys

SEG = 1448   # bytes per segment

# ── Load data ─────────────────────────────────────────────────────────
flows = {1: {'t': [], 'cwnd': [], 'rtt': [], 'gamma': []},
         2: {'t': [], 'cwnd': [], 'rtt': [], 'gamma': []},
         3: {'t': [], 'cwnd': [], 'rtt': [], 'gamma': []},
         4: {'t': [], 'cwnd': [], 'rtt': [], 'gamma': []}}

try:
    with open("comparison.dat") as f:
        for line in f:
            parts = line.split()
            if len(parts) != 5:
                continue
            fid = int(parts[0])
            if fid not in flows:
                continue
            flows[fid]['t'].append(float(parts[1]))
            flows[fid]['cwnd'].append(float(parts[2]) / SEG)  # bytes → packets
            flows[fid]['rtt'].append(float(parts[3]))         # ms
            flows[fid]['gamma'].append(float(parts[4]))
except FileNotFoundError:
    print("Error: comparison.dat not found. Run the simulation first.", file=sys.stderr)
    sys.exit(1)

# Convert to numpy arrays
for fid in flows:
    for key in flows[fid]:
        flows[fid][key] = np.array(flows[fid][key])

# ── Style ─────────────────────────────────────────────────────────────
STYLES = {
    1: dict(color="red",     linestyle="-",  linewidth=1.4, label="Original CUBIC-1"),
    2: dict(color="blue",    linestyle="-",  linewidth=1.4, label="Original CUBIC-2"),
    3: dict(color="green",   linestyle="--", linewidth=1.6, label="RTT-Aware CUBIC-1"),
    4: dict(color="magenta", linestyle="--", linewidth=1.6, label="RTT-Aware CUBIC-2"),
}

# ═══════════════════════════════════════════════════════════════════════
# Figure 1: CWND Comparison — 1 Original vs 1 RTT-Aware
# ═══════════════════════════════════════════════════════════════════════
fig1, ax1 = plt.subplots(figsize=(10, 5))

# Plot flow 1 (Original CUBIC) and flow 3 (RTT-Aware CUBIC)
ax1.plot(flows[1]['t'], flows[1]['cwnd'], **STYLES[1])
ax1.plot(flows[3]['t'], flows[3]['cwnd'], **STYLES[3])

ax1.set_xlabel("Time (s)", fontsize=12)
ax1.set_ylabel("CWND (packets)", fontsize=12)
ax1.set_title("CWND Comparison: Original CUBIC vs RTT-Aware CUBIC\n"
              "[50 Mbps, RTT = 100 ms, RED+ECN queue]",
              fontsize=12)
ax1.legend(fontsize=10, loc="upper right")
ax1.grid(True, linestyle="--", alpha=0.35)
ax1.set_xlim(0, 60)
fig1.tight_layout()
fig1.savefig("comparison-cwnd-single.png", dpi=150)
print("Saved comparison-cwnd-single.png")

# ═══════════════════════════════════════════════════════════════════════
# Figure 2: CWND Convergence — All 4 flows
# ═══════════════════════════════════════════════════════════════════════
fig2, ax2 = plt.subplots(figsize=(12, 5))

for fid in [1, 2, 3, 4]:
    ax2.plot(flows[fid]['t'], flows[fid]['cwnd'], **STYLES[fid])

ax2.set_xlabel("Time (s)", fontsize=12)
ax2.set_ylabel("CWND (packets)", fontsize=12)
ax2.set_title("CWND Convergence: 2 Original CUBIC + 2 RTT-Aware CUBIC\n"
              "[50 Mbps, RTT = 100 ms, RED+ECN queue]",
              fontsize=12)
ax2.legend(fontsize=10, loc="upper right")
ax2.grid(True, linestyle="--", alpha=0.35)
ax2.set_xlim(0, 60)
fig2.tight_layout()
fig2.savefig("comparison-cwnd-all.png", dpi=150)
print("Saved comparison-cwnd-all.png")

# ═══════════════════════════════════════════════════════════════════════
# Figure 3: RTT and Gamma Evolution (RTT-Aware flows only)
# ═══════════════════════════════════════════════════════════════════════
fig3, (ax3a, ax3b) = plt.subplots(2, 1, figsize=(10, 7), sharex=True)

# Top subplot: RTT evolution
ax3a.plot(flows[3]['t'], flows[3]['rtt'], color="green", linestyle="-",
          linewidth=1.2, label="RTT-Aware CUBIC-1")
ax3a.plot(flows[4]['t'], flows[4]['rtt'], color="magenta", linestyle="-",
          linewidth=1.2, label="RTT-Aware CUBIC-2")
ax3a.set_ylabel("RTT (ms)", fontsize=11)
ax3a.set_title("RTT Evolution: RTT-Aware CUBIC Flows\n"
               "[50 Mbps, RTT baseline = 100 ms]",
               fontsize=12)
ax3a.legend(fontsize=9, loc="upper right")
ax3a.grid(True, alpha=0.3)

# Bottom subplot: Gamma evolution
ax3b.plot(flows[3]['t'], flows[3]['gamma'], color="green", linestyle="-",
          linewidth=1.2, label="Gamma (RTT-Aware CUBIC-1)")
ax3b.plot(flows[4]['t'], flows[4]['gamma'], color="magenta", linestyle="-",
          linewidth=1.2, label="Gamma (RTT-Aware CUBIC-2)")
ax3b.axhline(1.0, color="gray", linestyle="--", linewidth=0.8, label="γ = 1 (neutral)")
ax3b.set_xlabel("Time (s)", fontsize=11)
ax3b.set_ylabel("Gamma (γ)", fontsize=11)
ax3b.set_title("Gamma Adjustment Factor\n"
               "[γ < 1: slow growth (RTT increasing), γ > 1: speed up (RTT decreasing)]",
               fontsize=10)
ax3b.legend(fontsize=9, loc="upper right")
ax3b.grid(True, alpha=0.3)
ax3b.set_ylim(0.4, 1.6)
ax3b.set_xlim(0, 60)

fig3.tight_layout()
fig3.savefig("comparison-rtt-gamma.png", dpi=150)
print("Saved comparison-rtt-gamma.png")

# ═══════════════════════════════════════════════════════════════════════
# Statistics
# ═══════════════════════════════════════════════════════════════════════
print("\n--- Steady-State Statistics (t > 20s) ---")
for fid in [1, 2, 3, 4]:
    mask = flows[fid]['t'] > 20.0
    if mask.sum() == 0:
        continue

    cwnd_mean = flows[fid]['cwnd'][mask].mean()
    cwnd_max  = flows[fid]['cwnd'][mask].max()
    cwnd_std  = flows[fid]['cwnd'][mask].std()

    label = "Original" if fid <= 2 else "RTT-Aware"
    print(f"Flow {fid} ({label:9s}): "
          f"mean={cwnd_mean:6.1f} pkts, "
          f"max={cwnd_max:6.1f} pkts, "
          f"std={cwnd_std:5.1f} pkts")

# Gamma statistics for RTT-Aware flows
print("\n--- Gamma Statistics (RTT-Aware flows, t > 20s) ---")
for fid in [3, 4]:
    mask = flows[fid]['t'] > 20.0
    if mask.sum() == 0:
        continue

    gamma_mean = flows[fid]['gamma'][mask].mean()
    gamma_min  = flows[fid]['gamma'][mask].min()
    gamma_max  = flows[fid]['gamma'][mask].max()

    print(f"Flow {fid}: "
          f"mean γ={gamma_mean:.3f}, "
          f"min={gamma_min:.3f}, "
          f"max={gamma_max:.3f}")
