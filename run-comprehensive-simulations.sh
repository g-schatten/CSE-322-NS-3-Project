#!/bin/bash

# Master simulation runner for comprehensive network evaluation
# This script runs all parameter combinations for wired and wireless networks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STUDENT_ID_MOD=0  # student_id % 8 = 0 → wired + wireless 802.11 (mobile)
NETWORK_TYPES=("wired" "wireless")
NODE_COUNTS=(20 40 60 80 100)
FLOW_COUNTS=(10 20 30 40 50)
PKT_RATES=(100 200 300 400 500)
NODE_SPEEDS=(5 10 15 20 25)
COVERAGE_MULTIPLIERS=(1 2 3 4 5)

# Results directory
RESULTS_DIR="comprehensive_results"
mkdir -p "$RESULTS_DIR"

# Build counter
TOTAL_SIMS=$(( ${#NETWORK_TYPES[@]} * ${#NODE_COUNTS[@]} * ${#FLOW_COUNTS[@]} * ${#PKT_RATES[@]} * ${#NODE_SPEEDS[@]} ))
QUICK_SIMS=$(( ${#NETWORK_TYPES[@]} * 2 * 2 * 2 * 2 ))  # Quick subset: 2 values each

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  RTT-Aware CUBIC - Comprehensive Network Simulation Suite      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Network types: ${NETWORK_TYPES[@]}"
echo "  Node counts: ${NODE_COUNTS[@]}"
echo "  Flow counts: ${FLOW_COUNTS[@]}"
echo "  Packet rates: ${PKT_RATES[@]} pkt/sec"
echo "  Node speeds (wireless): ${NODE_SPEEDS[@]} m/s"
echo "  Coverage multipliers: ${COVERAGE_MULTIPLIERS[@]}"
echo ""
echo "  Total possible simulations: $TOTAL_SIMS"
echo "  Quick test simulations: $QUICK_SIMS"
echo "  Recommended: Start with QUICK mode, then run FULL"
echo ""

# Function to run a single simulation
run_simulation() {
    local net_type=$1
    local num_nodes=$2
    local num_flows=$3
    local pkt_rate=$4
    local node_speed=$5
    local coverage_mult=$6

    echo -ne "  [$(printf '%3d' $CURRENT_SIM)/$TOTAL_RUNS] $net_type | N=$num_nodes F=$num_flows PPS=$pkt_rate"

    if [ "$net_type" = "wireless" ]; then
        echo -ne " SPD=${node_speed}m/s"
    else
        echo -ne " COV=${coverage_mult}x"
    fi
    echo -ne "... "

    # Run the simulation
    ./ns3 run "scratch/cubic-networks-simulation \
        --networkType=$net_type \
        --numNodes=$num_nodes \
        --numFlows=$num_flows \
        --pktPerSec=$pkt_rate \
        --nodeSpeed=$node_speed \
        --coverageMultiplier=$coverage_mult" \
        > /tmp/sim_${net_type}_${num_nodes}_${num_flows}_${pkt_rate}.log 2>&1

    echo -e "${GREEN}✓${NC}"
    ((CURRENT_SIM++))
}

# Parse command line arguments
MODE="QUICK"
if [ "$1" = "FULL" ]; then
    MODE="FULL"
elif [ "$1" = "QUICK" ]; then
    MODE="QUICK"
elif [ -n "$1" ]; then
    echo "Usage: $0 [QUICK|FULL]"
    echo "  QUICK: Run subset for testing (default, ~16 simulations)"
    echo "  FULL:  Run all parameter combinations (~1250 simulations)"
    exit 1
fi

echo -e "${YELLOW}Mode: ${MODE}${NC}"
echo ""

# Build the simulation first
echo -e "${BLUE}[STEP 1] Building ns-3 simulation...${NC}"
./ns3 build scratch/cubic-networks-simulation > /dev/null 2>&1 || {
    echo -e "${RED}Build failed!${NC}"
    exit 1
}
echo -e "${GREEN}✓ Build complete${NC}"
echo ""

# Prepare header for CSV
CSV_FILE="$RESULTS_DIR/all_results.csv"
if [ ! -f "$CSV_FILE" ]; then
    echo "NetworkType,NumNodes,NumFlows,PktPerSec,NodeSpeed,CoverageArea,Throughput(Mbps),AvgDelay(ms),PDR,DRR,Energy" > "$CSV_FILE"
fi

# Run simulations
echo -e "${BLUE}[STEP 2] Running simulations...${NC}"
CURRENT_SIM=1

if [ "$MODE" = "QUICK" ]; then
    # Quick mode: limited parameter values
    TOTAL_RUNS=$QUICK_SIMS
    echo "Running quick test (2 samples of each parameter): $TOTAL_RUNS simulations"
    echo ""

    for net_type in "${NETWORK_TYPES[@]}"; do
        for num_nodes in 20 80; do
            for num_flows in 10 40; do
                for pkt_rate in 100 400; do
                    if [ "$net_type" = "wireless" ]; then
                        run_simulation "$net_type" "$num_nodes" "$num_flows" "$pkt_rate" 10 1
                    else
                        run_simulation "$net_type" "$num_nodes" "$num_flows" "$pkt_rate" 5 2
                    fi
                done
            done
        done
    done
else
    # Full mode: all parameter values
    TOTAL_RUNS=$TOTAL_SIMS
    echo "Running full parameter sweep: $TOTAL_RUNS simulations (this will take a while)"
    echo "Estimated time: ~${TOTAL_RUNS} minutes (1 min per simulation)"
    echo ""

    for net_type in "${NETWORK_TYPES[@]}"; do
        for num_nodes in "${NODE_COUNTS[@]}"; do
            for num_flows in "${FLOW_COUNTS[@]}"; do
                for pkt_rate in "${PKT_RATES[@]}"; do
                    if [ "$net_type" = "wireless" ]; then
                        for node_speed in "${NODE_SPEEDS[@]}"; do
                            run_simulation "$net_type" "$num_nodes" "$num_flows" "$pkt_rate" "$node_speed" 1
                        done
                    else
                        for coverage_mult in "${COVERAGE_MULTIPLIERS[@]}"; do
                            run_simulation "$net_type" "$num_nodes" "$num_flows" "$pkt_rate" 5 "$coverage_mult"
                        done
                    fi
                done
            done
        done
    done
fi

echo ""
echo -e "${GREEN}[STEP 2] Simulations complete!${NC}"
echo ""

# Consolidate results
echo -e "${BLUE}[STEP 3] Consolidating results...${NC}"

# Collect CSV files
for file in results_*.csv; do
    if [ -f "$file" ]; then
        tail -n +2 "$file" >> "$CSV_FILE" 2>/dev/null || true
        rm "$file"
    fi
done

echo -e "${GREEN}✓ Results consolidated to: $CSV_FILE${NC}"
echo -e "${GREEN}✓ Total data points: $(tail -n +2 $CSV_FILE | wc -l)${NC}"
echo ""

# Generate plots
echo -e "${BLUE}[STEP 4] Generating plots...${NC}"

python3 << 'PYTHON_PLOT'
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
import sys

try:
    df = pd.read_csv('comprehensive_results/all_results.csv')
except:
    print("Warning: No results CSV found yet. Run simulations first.")
    sys.exit(0)

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 6)

# Create output directory
import os
os.makedirs('comprehensive_results/plots', exist_ok=True)

print("Generating plots...")

# 1. Throughput vs Number of Nodes
if 'NumNodes' in df.columns and 'Throughput(Mbps)' in df.columns:
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    for net_type in df['NetworkType'].unique():
        data = df[df['NetworkType'] == net_type]
        grouped = data.groupby('NumNodes')['Throughput(Mbps)'].mean()
        ax1.plot(grouped.index, grouped.values, marker='o', label=net_type.capitalize())

    ax1.set_xlabel('Number of Nodes')
    ax1.set_ylabel('Throughput (Mbps)')
    ax1.set_title('Throughput vs Number of Nodes')
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    for net_type in df['NetworkType'].unique():
        data = df[df['NetworkType'] == net_type]
        grouped = data.groupby('NumFlows')['Throughput(Mbps)'].mean()
        ax2.plot(grouped.index, grouped.values, marker='s', label=net_type.capitalize())

    ax2.set_xlabel('Number of Flows')
    ax2.set_ylabel('Throughput (Mbps)')
    ax2.set_title('Throughput vs Number of Flows')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig('comprehensive_results/plots/01_throughput.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  ✓ Throughput plot saved")

# 2. Delay vs Packet Rate
if 'PktPerSec' in df.columns and 'AvgDelay(ms)' in df.columns:
    fig, ax = plt.subplots(figsize=(12, 6))

    for net_type in df['NetworkType'].unique():
        data = df[df['NetworkType'] == net_type]
        grouped = data.groupby('PktPerSec')['AvgDelay(ms)'].mean()
        ax.plot(grouped.index, grouped.values, marker='D', label=net_type.capitalize(), linewidth=2)

    ax.set_xlabel('Packets Per Second')
    ax.set_ylabel('Average Delay (ms)')
    ax.set_title('End-to-End Delay vs Packet Rate')
    ax.legend()
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig('comprehensive_results/plots/02_delay.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  ✓ Delay plot saved")

# 3. Packet Delivery Ratio
if 'PDR' in df.columns:
    fig, ax = plt.subplots(figsize=(12, 6))

    for net_type in df['NetworkType'].unique():
        data = df[df['NetworkType'] == net_type]
        grouped = data.groupby('NumFlows')['PDR'].mean()
        ax.plot(grouped.index, grouped.values * 100, marker='^', label=net_type.capitalize(), linewidth=2)

    ax.set_xlabel('Number of Flows')
    ax.set_ylabel('PDR (%)')
    ax.set_title('Packet Delivery Ratio vs Number of Flows')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_ylim([0, 105])
    plt.tight_layout()
    plt.savefig('comprehensive_results/plots/03_pdr.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  ✓ PDR plot saved")

# 4. Packet Drop Ratio
if 'DRR' in df.columns:
    fig, ax = plt.subplots(figsize=(12, 6))

    for net_type in df['NetworkType'].unique():
        data = df[df['NetworkType'] == net_type]
        grouped = data.groupby('NumFlows')['DRR'].mean()
        ax.plot(grouped.index, grouped.values * 100, marker='x', label=net_type.capitalize(), linewidth=2)

    ax.set_xlabel('Number of Flows')
    ax.set_ylabel('DRR (%)')
    ax.set_title('Packet Drop Ratio vs Number of Flows')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_ylim([0, max(105, df['DRR'].max() * 100 + 10)])
    plt.tight_layout()
    plt.savefig('comprehensive_results/plots/04_drr.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  ✓ DRR plot saved")

# 5. Heatmap: Throughput by Nodes and Flows
if all(col in df.columns for col in ['NumNodes', 'NumFlows', 'Throughput(Mbps)', 'NetworkType']):
    for net_type in df['NetworkType'].unique():
        data = df[df['NetworkType'] == net_type]
        pivot = data.pivot_table(values='Throughput(Mbps)', index='NumNodes', columns='NumFlows', aggfunc='mean')

        fig, ax = plt.subplots(figsize=(10, 6))
        sns.heatmap(pivot, annot=True, fmt='.2f', cmap='YlGn', ax=ax, cbar_kws={'label': 'Throughput (Mbps)'})
        ax.set_title(f'Throughput Heatmap - {net_type.capitalize()} Network')
        plt.tight_layout()
        plt.savefig(f'comprehensive_results/plots/05_heatmap_{net_type}.png', dpi=150, bbox_inches='tight')
        plt.close()
    print("  ✓ Heatmap plots saved")

print("All plots generated!")

PYTHON_PLOT

echo -e "${GREEN}✓ Plots generated${NC}"
echo ""

# Summary
echo -e "${BLUE}[STEP 5] Summary${NC}"
echo -e "${GREEN}Results saved in: $RESULTS_DIR/${NC}"
echo -e "${GREEN}CSV file: $CSV_FILE${NC}"
echo -e "${GREEN}Plots directory: $RESULTS_DIR/plots/${NC}"
echo ""

echo -e "${BLUE}Next steps:${NC}"
echo "  1. Review the CSV file for detailed metrics"
echo "  2. Check plots in comprehensive_results/plots/"
echo "  3. Run: python3 generate_report.py (when script is created)"
echo ""

echo -e "${GREEN}Simulation suite complete!${NC}"
