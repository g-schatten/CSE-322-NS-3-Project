#!/usr/bin/env python3
"""
Generate 25 plots from viva sweep results:
  5 metrics x 5 parameter-variation groups.

Each plot contains two subplots:
  - Wired
  - Wireless

Each subplot compares both TCP variants:
  - custom
  - rtt-aware
"""

from pathlib import Path
import argparse
import csv
import matplotlib.pyplot as plt


PARAM_CONFIG = {
    "numNodes": {
        "column": "NumNodes",
        "x_values": [20, 40, 60, 80, 100],
        "xlabel": "Number of Nodes",
        "slug": "p1_nodes",
    },
    "numFlows": {
        "column": "NumFlows",
        "x_values": [10, 20, 30, 40, 50],
        "xlabel": "Number of Flows",
        "slug": "p2_flows",
    },
    "pktPerSec": {
        "column": "PktPerSec",
        "x_values": [100, 200, 300, 400, 500],
        "xlabel": "Packets per Second",
        "slug": "p3_pps",
    },
    "nodeSpeed": {
        "column": "NodeSpeed",
        "x_values": [5, 10, 15, 20, 25],
        "xlabel": "Node Speed (m/s)",
        "slug": "p4_speed",
    },
    "coverageMultiplier": {
        "column": "CoverageMultiplier",
        "x_values": [1, 2, 3, 4, 5],
        "xlabel": "Coverage Multiplier (x Tx_range)",
        "slug": "p5_coverage",
    },
}

METRICS = {
    "ThroughputMbps": {"ylabel": "Throughput (Mbps)", "slug": "throughput", "scale": 1.0},
    "AvgDelayMs": {"ylabel": "End-to-End Delay (ms)", "slug": "delay", "scale": 1.0},
    "PDR": {"ylabel": "Packet Delivery Ratio (%)", "slug": "pdr", "scale": 100.0},
    "DRR": {"ylabel": "Packet Drop Ratio (%)", "slug": "drr", "scale": 100.0},
    "EnergyJ": {"ylabel": "Energy Consumption (J)", "slug": "energy", "scale": 1.0},
}

TCP_STYLES = {
    "custom": {"label": "TCP CUBIC Custom", "color": "#d62728", "marker": "o"},
    "rtt-aware": {"label": "TCP CUBIC RTT-Aware", "color": "#1f77b4", "marker": "s"},
}


def make_plot(rows, metric_key, varied_param, out_dir):
    metric = METRICS[metric_key]
    p = PARAM_CONFIG[varied_param]
    x_col = p["column"]

    fig, axes = plt.subplots(1, 2, figsize=(13, 4.8), sharey=True)
    networks = ["wired", "wireless"]

    for ax, net in zip(axes, networks):
        net_df = [
            r for r in rows
            if r["NetworkType"] == net and r["VariedParam"] == varied_param
        ]

        if not net_df:
            ax.text(0.5, 0.5, "No data for this network/parameter",
                    ha="center", va="center", transform=ax.transAxes)
            ax.set_title(net.capitalize())
            ax.set_xlabel(p["xlabel"])
            ax.grid(True, alpha=0.3)
            continue

        for tcp, style in TCP_STYLES.items():
            tcp_df = [r for r in net_df if r["TcpVariant"] == tcp]
            if not tcp_df:
                continue
            tcp_df = sorted(tcp_df, key=lambda r: r[x_col])
            x = [r[x_col] for r in tcp_df]
            y = [r[metric_key] * metric["scale"] for r in tcp_df]
            ax.plot(x, y, linewidth=2, markersize=6, **style)

        ax.set_title(net.capitalize())
        ax.set_xlabel(p["xlabel"])
        ax.set_xticks(p["x_values"])
        ax.grid(True, alpha=0.3)
        ax.legend()

    axes[0].set_ylabel(metric["ylabel"])
    fig.suptitle(f"{metric['ylabel']} vs {p['xlabel']} (Varied: {varied_param})", fontsize=12)
    fig.tight_layout(rect=[0, 0, 1, 0.95])

    out_name = f"{metric['slug']}__{p['slug']}.png"
    out_path = out_dir / out_name
    fig.savefig(out_path, dpi=180)
    plt.close(fig)
    print(f"Saved {out_path}")


def main():
    parser = argparse.ArgumentParser(description="Generate 25 viva metric plots")
    parser.add_argument("--input", default="network_results/viva_all_results.csv")
    parser.add_argument("--output-dir", default="network_results/viva_plots")
    args = parser.parse_args()

    in_path = Path(args.input)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    with in_path.open() as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows.append({
                "NetworkType": r["NetworkType"],
                "TcpVariant": r["TcpVariant"],
                "VariedParam": r["VariedParam"],
                "NumNodes": float(r["NumNodes"]),
                "NumFlows": float(r["NumFlows"]),
                "PktPerSec": float(r["PktPerSec"]),
                "NodeSpeed": float(r["NodeSpeed"]),
                "CoverageMultiplier": float(r["CoverageMultiplier"]),
                "ThroughputMbps": float(r["ThroughputMbps"]),
                "AvgDelayMs": float(r["AvgDelayMs"]),
                "PDR": float(r["PDR"]),
                "DRR": float(r["DRR"]),
                "EnergyJ": float(r["EnergyJ"]),
            })

    for metric_key in METRICS:
        for varied_param in PARAM_CONFIG:
            make_plot(rows, metric_key, varied_param, out_dir)

    print(f"\nDone. Generated 25 plots in: {out_dir}")


if __name__ == "__main__":
    main()
