#!/usr/bin/env python3
"""
run-parameter-sweep.py
Automates parameter tuning experiments

Usage:
  ./run-parameter-sweep.py --k 0.5 1.0 1.5 --alpha 0.125 0.0625
  → Runs 6 experiments (3 K values × 2 alpha values)

  ./run-parameter-sweep.py --k 0.5 --gamma-bounds 0.5,1.5 0.7,1.3
  → Runs 2 experiments with different gamma clamps

Output:
  - Creates experiment_K{k}_Alpha{alpha}/ directories
  - Each contains: comparison.dat, comparison-*.png, stats.txt
"""

import subprocess
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime

def run_experiment(k, alpha, gamma_min, gamma_max, exp_dir):
    """Run one experiment with given parameters."""
    print(f"\n{'='*70}")
    print(f"Experiment: K={k}, Alpha={alpha}, GammaMin={gamma_min}, GammaMax={gamma_max}")
    print(f"Output: {exp_dir}")
    print(f"{'='*70}\n")

    # Create experiment directory
    Path(exp_dir).mkdir(parents=True, exist_ok=True)

    # Write a temporary scratch file with Config::SetDefault calls
    # We'll modify the simulation before running
    # For now, just use environment or modify via cmake

    # Build (should be fast since already built)
    print("[1/3] Building...")
    build_result = subprocess.run(
        ["./ns3", "build", "scratch/test-cubic-comparison"],
        capture_output=True, text=True
    )
    if build_result.returncode != 0:
        print(f"Build failed:\n{build_result.stderr}")
        return False

    # Run simulation with parameters via environment or command line
    print("[2/3] Running simulation...")
    run_cmd = [
        "./ns3", "run", "scratch/test-cubic-comparison",
        "--",
        f"--K={k}",
        f"--Alpha={alpha}",
        f"--GammaMin={gamma_min}",
        f"--GammaMax={gamma_max}"
    ]

    output_file = os.path.join(exp_dir, "comparison.dat")
    with open(output_file, "w") as out_f:
        run_result = subprocess.run(
            run_cmd,
            stdout=out_f,
            stderr=subprocess.DEVNULL
        )

    if run_result.returncode != 0:
        print(f"Simulation failed")
        return False

    print(f"   Simulation complete. Output: {output_file}")

    # Generate plots
    print("[3/3] Generating plots...")
    plot_cmd = [".venv/bin/python3", "plot-rtt-comparison.py"]

    # Change to experiment directory, run plotter, then change back
    cwd = os.getcwd()
    try:
        os.chdir(exp_dir)
        # Copy comparison.dat from parent, run plotter
        plot_result = subprocess.run(
            plot_cmd,
            capture_output=True,
            text=True,
            cwd=exp_dir
        )
        if plot_result.returncode != 0:
            print(f"Plot generation had issues:\n{plot_result.stderr}")
        else:
            print(plot_result.stdout)
    finally:
        os.chdir(cwd)

    # Save metadata
    metadata_file = os.path.join(exp_dir, "parameters.txt")
    with open(metadata_file, "w") as f:
        f.write(f"Timestamp: {datetime.now().isoformat()}\n")
        f.write(f"K (Sensitivity): {k}\n")
        f.write(f"Alpha (EWMA weight): {alpha}\n")
        f.write(f"GammaMin: {gamma_min}\n")
        f.write(f"GammaMax: {gamma_max}\n")

    print(f"✓ Experiment complete: {exp_dir}\n")
    return True


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run parameter sweep experiments for RTT-Aware CUBIC"
    )
    parser.add_argument("--k", nargs="+", type=float, default=[0.5],
                        help="K (sensitivity) values to test")
    parser.add_argument("--alpha", nargs="+", type=float, default=[0.125],
                        help="Alpha (EWMA) values to test")
    parser.add_argument("--gamma-min", nargs="+", type=float, default=[0.5],
                        help="GammaMin values to test")
    parser.add_argument("--gamma-max", nargs="+", type=float, default=[1.5],
                        help="GammaMax values to test")
    parser.add_argument("--output-dir", type=str, default="param_sweep_results",
                        help="Base output directory for all experiments")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what experiments would run without running them")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    # Generate all combinations
    experiments = []
    for k in args.k:
        for alpha in args.alpha:
            for gamma_min in args.gamma_min:
                for gamma_max in args.gamma_max:
                    exp_name = f"K{k:.2f}_Alpha{alpha:.4f}_GMin{gamma_min:.2f}_GMax{gamma_max:.2f}"
                    exp_dir = os.path.join(args.output_dir, exp_name)
                    experiments.append((k, alpha, gamma_min, gamma_max, exp_dir))

    print(f"Parameter Sweep: {len(experiments)} experiment(s)")
    print("=" * 70)

    for i, (k, alpha, gamma_min, gamma_max, exp_dir) in enumerate(experiments, 1):
        print(f"\n[{i}/{len(experiments)}] {os.path.basename(exp_dir)}")

        if args.dry_run:
            print(f"   Would run: K={k}, Alpha={alpha}, GammaMin={gamma_min}, GammaMax={gamma_max}")
            continue

        success = run_experiment(k, alpha, gamma_min, gamma_max, exp_dir)
        if not success:
            print(f"⚠ Experiment failed, continuing with next...")

    print("\n" + "=" * 70)
    print(f"Results saved in: {args.output_dir}/")
    print("\nTo compare results:")
    print(f"  ls {args.output_dir}/*/comparison-*.png")
    print(f"  for dir in {args.output_dir}/*/; do echo $dir; tail -20 $dir/comparison-* | grep 'Flow'; done")
