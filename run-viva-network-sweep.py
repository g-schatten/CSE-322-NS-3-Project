#!/usr/bin/env python3
import argparse
import csv
import subprocess
from pathlib import Path


NODES = [20, 40, 60, 80, 100]
FLOWS = [10, 20, 30, 40, 50]
PPS = [100, 200, 300, 400, 500]
SPEEDS = [5, 10, 15, 20, 25]
COVERAGE = [1, 2, 3, 4, 5]

BASELINE = {
    "numNodes": 60,
    "numFlows": 30,
    "pktPerSec": 300,
    "nodeSpeed": 15.0,
    "coverageMultiplier": 3,
}


def make_cases(network_type: str):
    # Generate "vary one, fix others", deduplicated.
    cases = {}

    def add_case(**kwargs):
        case = {
            "numNodes": BASELINE["numNodes"],
            "numFlows": BASELINE["numFlows"],
            "pktPerSec": BASELINE["pktPerSec"],
            "nodeSpeed": BASELINE["nodeSpeed"],
            "coverageMultiplier": BASELINE["coverageMultiplier"],
            "variedParam": kwargs["variedParam"],
        }
        case.update(kwargs["values"])
        key = (
            case["numNodes"],
            case["numFlows"],
            case["pktPerSec"],
            case["nodeSpeed"],
            case["coverageMultiplier"],
        )
        cases[key] = case

    for v in NODES:
        add_case(variedParam="numNodes", values={"numNodes": v})
    for v in FLOWS:
        add_case(variedParam="numFlows", values={"numFlows": v})
    for v in PPS:
        add_case(variedParam="pktPerSec", values={"pktPerSec": v})

    if network_type == "wireless":
        for v in SPEEDS:
            add_case(variedParam="nodeSpeed", values={"nodeSpeed": float(v)})
    else:
        for v in COVERAGE:
            add_case(variedParam="coverageMultiplier", values={"coverageMultiplier": v})

    return list(cases.values())


def parse_csv_row(output: str):
    for line in output.splitlines():
        if line.startswith("CSV_ROW,"):
            parts = line.strip().split(",")
            return {
                "NetworkType": parts[1],
                "TcpVariant": parts[2],
                "NumNodes": int(parts[3]),
                "NumFlows": int(parts[4]),
                "PktPerSec": int(parts[5]),
                "NodeSpeed": float(parts[6]),
                "CoverageMultiplier": int(parts[7]),
                "ThroughputMbps": float(parts[8]),
                "AvgDelayMs": float(parts[9]),
                "PDR": float(parts[10]),
                "DRR": float(parts[11]),
                "EnergyJ": float(parts[12]),
            }
    return None


def run_case(case, network_type, tcp_variant, sim_time):
    cmd = [
        "./ns3",
        "run",
        (
            "scratch/cubic-networks-simulation"
            f" --networkType={network_type}"
            f" --tcpVariant={tcp_variant}"
            f" --numNodes={case['numNodes']}"
            f" --numFlows={case['numFlows']}"
            f" --pktPerSec={case['pktPerSec']}"
            f" --nodeSpeed={case['nodeSpeed']}"
            f" --coverageMultiplier={case['coverageMultiplier']}"
            f" --simTime={sim_time}"
        ),
    ]

    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr[-8000:])

    row = parse_csv_row(proc.stdout)
    if not row:
        raise RuntimeError("Simulation completed but CSV_ROW was not found in output")
    row["VariedParam"] = case["variedParam"]
    return row


def main():
    parser = argparse.ArgumentParser(description="Run viva parameter sweeps for wired/wireless and both TCP variants")
    parser.add_argument("--output", default="network_results/viva_all_results.csv")
    parser.add_argument("--sim-time", type=float, default=30.0)
    parser.add_argument("--build", action="store_true", help="Build scratch simulation before running")
    args = parser.parse_args()

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if args.build:
        b = subprocess.run(["./ns3", "build", "scratch/cubic-networks-simulation"], text=True)
        if b.returncode != 0:
            raise SystemExit("Build failed for scratch/cubic-networks-simulation")

    tcp_variants = ["custom", "rtt-aware"]
    network_types = ["wired", "wireless"]

    all_rows = []
    total = 0
    for net in network_types:
        total += len(make_cases(net)) * len(tcp_variants)

    done = 0
    for net in network_types:
        cases = make_cases(net)
        for tcp in tcp_variants:
            for case in cases:
                done += 1
                print(
                    f"[{done}/{total}] net={net} tcp={tcp} "
                    f"N={case['numNodes']} F={case['numFlows']} PPS={case['pktPerSec']} "
                    f"SPD={case['nodeSpeed']} COV={case['coverageMultiplier']} var={case['variedParam']}"
                )
                row = run_case(case, net, tcp, args.sim_time)
                all_rows.append(row)

    with out_path.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "NetworkType",
                "TcpVariant",
                "VariedParam",
                "NumNodes",
                "NumFlows",
                "PktPerSec",
                "NodeSpeed",
                "CoverageMultiplier",
                "ThroughputMbps",
                "AvgDelayMs",
                "PDR",
                "DRR",
                "EnergyJ",
            ],
        )
        writer.writeheader()
        writer.writerows(all_rows)

    print(f"\nSaved {len(all_rows)} rows to {out_path}")


if __name__ == "__main__":
    main()
