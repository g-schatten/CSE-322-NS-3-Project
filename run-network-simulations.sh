#!/bin/bash

# Comprehensive Network Simulation Runner
# Evaluates RTT-Aware CUBIC over wired and wireless networks

set -e

BLUE='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration - Student ID % 8 = 0 → Wired + Wireless
NETWORK_TYPES=("wired" "wireless")

# Full parameter sets
NODE_COUNTS=(20 40 60)                    # Reduced for practical execution
FLOW_COUNTS=(10 20 30)                    # Reduced
PKT_RATES=(100 200 300)                   # Reduced
SPEEDS=(5 10 15)                          # For wireless
COVERAGE=(1 2 3)                          # For wired

RESULTS_DIR="network_results"
mkdir -p "$RESULTS_DIR"
CSV_FILE="$RESULTS_DIR/all_results.csv"

# Initialize CSV
echo "NetworkType,NumNodes,NumFlows,PktPerSec,NodeSpeed,CoverageArea,Throughput(Mbps),Delay(ms),PDR,DRR" > "$CSV_FILE"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  RTT-Aware CUBIC: Comprehensive Network Evaluation              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Count total simulations
WIRED_SIMS=$((${#NODE_COUNTS[@]} * ${#FLOW_COUNTS[@]} * ${#PKT_RATES[@]} * ${#COVERAGE[@]}))
WIRELESS_SIMS=$((${#NODE_COUNTS[@]} * ${#FLOW_COUNTS[@]} * ${#PKT_RATES[@]} * ${#SPEEDS[@]}))
TOTAL_SIMS=$((WIRED_SIMS + WIRELESS_SIMS))

echo -e "${GREEN}Configuration:${NC}"
echo "  Networks: ${NETWORK_TYPES[@]}"
echo "  Nodes: ${NODE_COUNTS[@]}"
echo "  Flows: ${FLOW_COUNTS[@]}"
echo "  Packet Rates: ${PKT_RATES[@]} pkt/sec"
echo "  Wireless Speeds: ${SPEEDS[@]} m/s"
echo "  Wired Coverage: ${COVERAGE[@]}x"
echo ""
echo "  Estimated simulations: $TOTAL_SIMS"
echo "  Estimated time: ~$((TOTAL_SIMS * 1)) minutes (1 min per sim)"
echo ""

# Run simulations
SIM_COUNT=0

for net_type in "${NETWORK_TYPES[@]}"; do
    for num_nodes in "${NODE_COUNTS[@]}"; do
        for num_flows in "${FLOW_COUNTS[@]}"; do
            for pkt_rate in "${PKT_RATES[@]}"; do
                if [ "$net_type" = "wireless" ]; then
                    for speed in "${SPEEDS[@]}"; do
                        ((SIM_COUNT++))
                        echo -ne "${BLUE}[$SIM_COUNT/$TOTAL_SIMS]${NC} wireless | N=$num_nodes F=$num_flows PPS=$pkt_rate SPD=${speed}m/s... "

                        timeout 120 ./ns3 run "scratch/cubic-networks-simulation \
                            --networkType=$net_type \
                            --numNodes=$num_nodes \
                            --numFlows=$num_flows \
                            --pktPerSec=$pkt_rate \
                            --nodeSpeed=$speed" \
                            > /tmp/sim.log 2>&1

                        # Extract results
                        if [ -f "results_${net_type}_${num_nodes}n_${num_flows}f_${pkt_rate}pps.csv" ]; then
                            tail -n 1 "results_${net_type}_${num_nodes}n_${num_flows}f_${pkt_rate}pps.csv" >> "$CSV_FILE"
                            rm "results_${net_type}_${num_nodes}n_${num_flows}f_${pkt_rate}pps.csv"
                            echo -e "${GREEN}✓${NC}"
                        else
                            echo -e "${YELLOW}⚠${NC} (no output)"
                        fi
                    done
                else
                    for cov in "${COVERAGE[@]}"; do
                        ((SIM_COUNT++))
                        echo -ne "${BLUE}[$SIM_COUNT/$TOTAL_SIMS]${NC} wired    | N=$num_nodes F=$num_flows PPS=$pkt_rate COV=${cov}x... "

                        timeout 120 ./ns3 run "scratch/cubic-networks-simulation \
                            --networkType=$net_type \
                            --numNodes=$num_nodes \
                            --numFlows=$num_flows \
                            --pktPerSec=$pkt_rate \
                            --coverageMultiplier=$cov" \
                            > /tmp/sim.log 2>&1

                        # Extract results
                        if [ -f "results_${net_type}_${num_nodes}n_${num_flows}f_${pkt_rate}pps.csv" ]; then
                            tail -n 1 "results_${net_type}_${num_nodes}n_${num_flows}f_${pkt_rate}pps.csv" >> "$CSV_FILE"
                            rm "results_${net_type}_${num_nodes}n_${num_flows}f_${pkt_rate}pps.csv"
                            echo -e "${GREEN}✓${NC}"
                        else
                            echo -e "${YELLOW}⚠${NC} (no output)"
                        fi
                    done
                fi
            done
        done
    done
done

echo ""
echo -e "${GREEN}✓ All simulations complete!${NC}"
echo -e "${GREEN}✓ Results saved to: $CSV_FILE${NC}"
echo ""

# Generate plots
echo -e "${BLUE}Generating plots...${NC}"

python3 << 'MATPLOTLIB_SCRIPT'
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

try:
    df = pd.read_csv('network_results/all_results.csv')
    if df.empty:
        print("Warning: No data in CSV file")
        exit(0)
except Exception as e:
    print(f"Error reading CSV: {e}")
    exit(1)

os.makedirs('network_results/plots', exist_ok=True)
sns.set_style("whitegrid")

# 1. Throughput vs Nodes (by network type)
fig, ax = plt.subplots(figsize=(12, 6))
for net_type in df['NetworkType'].unique():
    data = df[df['NetworkType'] == net_type].groupby('NumNodes')['Throughput(Mbps)'].mean()
    ax.plot(data.index, data.values, marker='o', label=net_type.capitalize(), linewidth=2)

ax.set_xlabel('Number of Nodes')
ax.set_ylabel('Throughput (Mbps)')
ax.set_title('Network Throughput vs Number of Nodes')
ax.legend()
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('network_results/plots/01_throughput_vs_nodes.png', dpi=150)
plt.close()
print("  ✓ Throughput vs Nodes")

# 2. Delay vs Packet Rate
fig, ax = plt.subplots(figsize=(12, 6))
for net_type in df['NetworkType'].unique():
    data = df[df['NetworkType'] == net_type].groupby('PktPerSec')['Delay(ms)'].mean()
    ax.plot(data.index, data.values, marker='s', label=net_type.capitalize(), linewidth=2)

ax.set_xlabel('Packets Per Second')
ax.set_ylabel('Delay (ms)')
ax.set_title('End-to-End Delay vs Packet Rate')
ax.legend()
ax.grid(True, alpha=0.3)
ax.set_yscale('log')
plt.tight_layout()
plt.savefig('network_results/plots/02_delay_vs_pktrate.png', dpi=150)
plt.close()
print("  ✓ Delay vs Packet Rate")

# 3. PDR vs Number of Flows
fig, ax = plt.subplots(figsize=(12, 6))
for net_type in df['NetworkType'].unique():
    data = df[df['NetworkType'] == net_type].groupby('NumFlows')['PDR'].mean() * 100
    ax.plot(data.index, data.values, marker='^', label=net_type.capitalize(), linewidth=2)

ax.set_xlabel('Number of Flows')
ax.set_ylabel('PDR (%)')
ax.set_title('Packet Delivery Ratio vs Number of Flows')
ax.legend()
ax.grid(True, alpha=0.3)
ax.set_ylim([0, 105])
plt.tight_layout()
plt.savefig('network_results/plots/03_pdr_vs_flows.png', dpi=150)
plt.close()
print("  ✓ PDR vs Flows")

# 4. DRR vs Number of Flows
fig, ax = plt.subplots(figsize=(12, 6))
for net_type in df['NetworkType'].unique():
    data = df[df['NetworkType'] == net_type].groupby('NumFlows')['DRR'].mean() * 100
    ax.plot(data.index, data.values, marker='x', label=net_type.capitalize(), linewidth=2)

ax.set_xlabel('Number of Flows')
ax.set_ylabel('DRR (%)')
ax.set_title('Packet Drop Ratio vs Number of Flows')
ax.legend()
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('network_results/plots/04_drr_vs_flows.png', dpi=150)
plt.close()
print("  ✓ DRR vs Flows")

# 5. Heatmap : Throughput by Nodes and Flows (Wired)
wired_df = df[df['NetworkType'] == 'wired']
if not wired_df.empty:
    pivot = wired_df.pivot_table(values='Throughput(Mbps)', index='NumNodes', columns='NumFlows', aggfunc='mean')
    fig, ax = plt.subplots(figsize=(10, 6))
    sns.heatmap(pivot, annot=True, fmt='.2f', cmap='YlGn', ax=ax, cbar_kws={'label': 'Throughput (Mbps)'})
    ax.set_title('Throughput Heatmap - Wired Network')
    plt.tight_layout()
    plt.savefig('network_results/plots/05_heatmap_wired.png', dpi=150)
    plt.close()
    print("  ✓ Heatmap (Wired)")

# 6. Heatmap: Throughput by Nodes and Flows (Wireless)
wireless_df = df[df['NetworkType'] == 'wireless']
if not wireless_df.empty:
    pivot = wireless_df.pivot_table(values='Throughput(Mbps)', index='NumNodes', columns='NumFlows', aggfunc='mean')
    fig, ax = plt.subplots(figsize=(10, 6))
    sns.heatmap(pivot, annot=True, fmt='.2f', cmap='YlGn', ax=ax, cbar_kws={'label': 'Throughput (Mbps)'})
    ax.set_title('Throughput Heatmap - Wireless Network')
    plt.tight_layout()
    plt.savefig('network_results/plots/06_heatmap_wireless.png', dpi=150)
    plt.close()
    print("  ✓ Heatmap (Wireless)")

# 7. Performance comparison box plot
fig, axes = plt.subplots(2, 2, figsize=(14, 10))

# Throughput
axes[0, 0].boxplot([df[df['NetworkType'] == 'wired']['Throughput(Mbps)'],
                     df[df['NetworkType'] == 'wireless']['Throughput(Mbps)']],
                    labels=['Wired', 'Wireless'])
axes[0, 0].set_ylabel('Throughput (Mbps)')
axes[0, 0].set_title('Throughput Distribution')
axes[0, 0].grid(True, alpha=0.3)

# Delay
axes[0, 1].boxplot([df[df['NetworkType'] == 'wired']['Delay(ms)'],
                     df[df['NetworkType'] == 'wireless']['Delay(ms)']],
                    labels=['Wired', 'Wireless'])
axes[0, 1].set_ylabel('Delay (ms)')
axes[0, 1].set_title('Delay Distribution')
axes[0, 1].grid(True, alpha=0.3)
axes[0, 1].set_yscale('log')

# PDR
axes[1, 0].boxplot([df[df['NetworkType'] == 'wired']['PDR'] * 100,
                     df[df['NetworkType'] == 'wireless']['PDR'] * 100],
                    labels=['Wired', 'Wireless'])
axes[1, 0].set_ylabel('PDR (%)')
axes[1, 0].set_title('PDR Distribution')
axes[1, 0].grid(True, alpha=0.3)
axes[1, 0].set_ylim([0, 105])

# DRR
axes[1, 1].boxplot([df[df['NetworkType'] == 'wired']['DRR'] * 100,
                     df[df['NetworkType'] == 'wireless']['DRR'] * 100],
                    labels=['Wired', 'Wireless'])
axes[1, 1].set_ylabel('DRR (%)')
axes[1, 1].set_title('DRR Distribution')
axes[1, 1].grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig('network_results/plots/07_performance_boxplots.png', dpi=150)
plt.close()
print("  ✓ Performance distributions")

print("\n✓ All plots generated!")

MATPLOTLIB_SCRIPT

echo -e "${GREEN}✓ Plotting complete!${NC}"
echo ""
echo -e "${BLUE}Results Summary:${NC}"
echo "  CSV: $CSV_FILE"
echo "  Plots: network_results/plots/"
echo "  Data points: $(tail -n +2 $CSV_FILE | wc -l)"
echo ""
echo -e "${GREEN}Ready to generate report!${NC}"
