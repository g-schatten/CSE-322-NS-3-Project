#!/usr/bin/env python3
import csv
from pathlib import Path
import matplotlib.pyplot as plt


def load_rows(path):
    rows = []
    with open(path) as f:
        r = csv.DictReader(f)
        for x in r:
            rows.append({
                "TcpVariant": x["TcpVariant"],
                "WiredNodes": int(x["WiredNodes"]),
                "WirelessNodes": int(x["WirelessNodes"]),
                "FlowsEachDirection": int(x["FlowsEachDirection"]),
                "PktPerSec": int(x["PktPerSec"]),
                "ThroughputMbps": float(x["ThroughputMbps"]),
                "AvgDelayMs": float(x["AvgDelayMs"]),
                "PDR": float(x["PDR"]),
                "DRR": float(x["DRR"]),
                "AvgJitterMs": float(x["AvgJitterMs"]),
                "MeanPerNodeThroughputMbps": float(x["MeanPerNodeThroughputMbps"]),
                "JainFairness": float(x["JainFairness"]),
            })
    return rows


def plot_metric(rows, x_key, metric_key, out_path, title, ylabel, scale=1.0):
    plt.figure(figsize=(8, 4.8))
    for tcp, marker, color in [("custom", "o", "#d62728"), ("rtt-aware", "s", "#1f77b4")]:
        d = [r for r in rows if r["TcpVariant"] == tcp and r["WiredNodes"] == 20 and r["WirelessNodes"] == 20]
        d.sort(key=lambda v: v[x_key])
        x = [r[x_key] for r in d]
        y = [r[metric_key] * scale for r in d]
        plt.plot(x, y, marker=marker, color=color, linewidth=2, label=tcp)
    plt.title(title)
    plt.xlabel(x_key)
    plt.ylabel(ylabel)
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_path, dpi=180)
    plt.close()
    print(f"Saved {out_path}")


def main():
    in_csv = Path("bonus_results/bonus_hybrid_results.csv")
    out_dir = Path("bonus_results/plots")
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = load_rows(in_csv)

    plot_metric(rows, "FlowsEachDirection", "ThroughputMbps",
                out_dir / "bonus_throughput_vs_flows.png",
                "Bonus Hybrid: Throughput vs FlowsEachDirection", "Throughput (Mbps)")
    plot_metric(rows, "FlowsEachDirection", "AvgDelayMs",
                out_dir / "bonus_delay_vs_flows.png",
                "Bonus Hybrid: Delay vs FlowsEachDirection", "Delay (ms)")
    plot_metric(rows, "FlowsEachDirection", "PDR",
                out_dir / "bonus_pdr_vs_flows.png",
                "Bonus Hybrid: PDR vs FlowsEachDirection", "PDR (%)", scale=100.0)
    plot_metric(rows, "FlowsEachDirection", "DRR",
                out_dir / "bonus_drr_vs_flows.png",
                "Bonus Hybrid: DRR vs FlowsEachDirection", "DRR (%)", scale=100.0)
    plot_metric(rows, "FlowsEachDirection", "AvgJitterMs",
                out_dir / "bonus_jitter_vs_flows.png",
                "Bonus Hybrid: Avg Jitter vs FlowsEachDirection", "Jitter (ms)")
    plot_metric(rows, "FlowsEachDirection", "MeanPerNodeThroughputMbps",
                out_dir / "bonus_pernode_tput_vs_flows.png",
                "Bonus Hybrid: Mean Per-Node Throughput vs FlowsEachDirection", "Mbps")
    plot_metric(rows, "FlowsEachDirection", "JainFairness",
                out_dir / "bonus_fairness_vs_flows.png",
                "Bonus Hybrid: Jain Fairness vs FlowsEachDirection", "Jain Fairness")


if __name__ == "__main__":
    main()

