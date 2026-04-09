#!/usr/bin/env python3
import csv
import subprocess
from pathlib import Path


def run_one(tcp, flows_each_dir, pps, wired_nodes, wireless_nodes):
    cmd = [
        "./ns3",
        "run",
        (
            "scratch/bonus-hybrid-cross-transmission"
            f" --tcpVariant={tcp}"
            f" --wiredNodes={wired_nodes}"
            f" --wirelessNodes={wireless_nodes}"
            f" --flowsEachDirection={flows_each_dir}"
            f" --pktPerSec={pps}"
            " --simTime=20"
        ),
    ]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[-4000:])
    for line in p.stdout.splitlines():
        if line.startswith("BONUS_CSV_ROW,"):
            parts = line.strip().split(",")
            return {
                "TcpVariant": parts[1],
                "WiredNodes": int(parts[2]),
                "WirelessNodes": int(parts[3]),
                "FlowsEachDirection": int(parts[4]),
                "PktPerSec": int(parts[5]),
                "ThroughputMbps": float(parts[6]),
                "AvgDelayMs": float(parts[7]),
                "PDR": float(parts[8]),
                "DRR": float(parts[9]),
                "AvgJitterMs": float(parts[10]),
                "MeanPerNodeThroughputMbps": float(parts[11]),
                "JainFairness": float(parts[12]),
            }
    raise RuntimeError("BONUS_CSV_ROW not found")


def main():
    out_dir = Path("bonus_results")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_csv = out_dir / "bonus_hybrid_results.csv"

    subprocess.run(["./ns3", "build", "scratch/bonus-hybrid-cross-transmission"], check=True)

    tcp_variants = ["custom", "rtt-aware"]
    flows_set = [5, 10, 15]
    pps_set = [100, 200, 300]
    node_pairs = [(10, 10), (20, 20)]  # (wired, wireless)

    rows = []
    total = len(tcp_variants) * len(flows_set) * len(pps_set) * len(node_pairs)
    idx = 0
    for tcp in tcp_variants:
        for flows in flows_set:
            for pps in pps_set:
                for wn, win in node_pairs:
                    idx += 1
                    print(f"[{idx}/{total}] tcp={tcp} flowsEachDir={flows} pps={pps} wired={wn} wireless={win}")
                    rows.append(run_one(tcp, flows, pps, wn, win))

    with out_csv.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "TcpVariant",
                "WiredNodes",
                "WirelessNodes",
                "FlowsEachDirection",
                "PktPerSec",
                "ThroughputMbps",
                "AvgDelayMs",
                "PDR",
                "DRR",
                "AvgJitterMs",
                "MeanPerNodeThroughputMbps",
                "JainFairness",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nSaved bonus results: {out_csv} ({len(rows)} rows)")


if __name__ == "__main__":
    main()

