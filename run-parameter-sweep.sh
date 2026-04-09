#!/bin/bash

# Comprehensive TCP CUBIC Parameter Sweep
# Systematically varies 5 parameters for both Wired and Wireless networks
# Compares tcp-cubic vs tcp-cubic-rtt-aware algorithms
# Measures: Throughput, Delay, PDR, DRR, Energy

set -e

BLUE='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

# 5 Parameters with 5 values each
NODES=(20 40 60 80 100)
FLOWS=(10 20 30 40 50)
PKT_RATES=(100 200 300 400 500)
SPEEDS=(5 10 15 20 25)     # Wireless only (mobile)
COVERAGE=(1 2 3 4 5)       # Wired only (static)

# Fixed baseline values
BASELINE_NODES=40
BASELINE_FLOWS=20
BASELINE_PKT_RATE=200
BASELINE_SPEED=10
BASELINE_COVERAGE=2

# Networks and algorithms
NETWORKS=("wired" "wireless")
ALGORITHMS=("cubic" "cubic-rtt-aware")

# Output directory
RESULTS_DIR="parameter_sweep_results"
mkdir -p "$RESULTS_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     TCP CUBIC - Comprehensive Parameter Sweep Study             ║${NC}"
echo -e "${BLUE}║     Evaluating both standard CUBIC and RTT-Aware variants       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Networks: Wired, Wireless 802.11 (Mobile)"
echo "  Algorithms: tcp-cubic, tcp-cubic-rtt-aware"
echo "  Parameters: Nodes (5), Flows (5), PktRate (5), Speed (5-wireless), Coverage (5-wired)"
echo "  Strategy: Vary each parameter while fixing others (20 simulations per network/algorithm)"
echo ""

# Calculate total simulations
# Wired: 5 (nodes) + 5 (flows) + 5 (pkt_rate) + 5 (coverage) = 20 per algorithm = 40 wired total
# Wireless: 5 (nodes) + 5 (flows) + 5 (pkt_rate) + 5 (speed) = 20 per algorithm = 40 wireless total
# Total: 80 simulations
TOTAL_SIMS=$((2 * 2 * 20))  # 2 networks × 2 algorithms × 20 combinations

echo -e "${YELLOW}Expected simulations: $TOTAL_SIMS${NC}"
echo -e "${YELLOW}Estimated time: ~$((TOTAL_SIMS * 2)) minutes (2 min per sim)${NC}"
echo ""

# Initialize master CSV files with headers
for network in "${NETWORKS[@]}"; do
    for algorithm in "${ALGORITHMS[@]}"; do
        csv="${RESULTS_DIR}/${network}_${algorithm}_comprehensive.csv"
        echo "Network,Algorithm,NumNodes,NumFlows,PktPerSec,NodeSpeed,CoverageMultiplier,Throughput_Mbps,Delay_ms,PDR_percent,DRR_percent,Energy_J" \
            > "$csv"
    done
done

echo -e "${GREEN}✓ CSV files initialized${NC}"
echo ""

# Counter
SIM_COUNT=0

# ══════════════════════════════════════════════════════════════════════════════
# SIMULATION LOOP
# ══════════════════════════════════════════════════════════════════════════════

for network in "${NETWORKS[@]}"; do
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Network: $network${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""

    for algorithm in "${ALGORITHMS[@]}"; do
        echo -e "${YELLOW}Algorithm: $algorithm${NC}"
        echo ""

        csv="${RESULTS_DIR}/${network}_${algorithm}_comprehensive.csv"

        # EXPERIMENT 1: Vary Number of Nodes
        echo "  [EXP 1] Varying Number of Nodes..."
        for nodes in "${NODES[@]}"; do
            ((SIM_COUNT++))
            echo -ne "    [$SIM_COUNT/$TOTAL_SIMS] nodes=$nodes... "

            timeout 120 ./ns3 run \
                "scratch/cubic-comprehensive-eval \
                --networkType=$network \
                --algorithm=$algorithm \
                --numNodes=$nodes \
                --numFlows=$BASELINE_FLOWS \
                --pktPerSec=$BASELINE_PKT_RATE \
                --nodeSpeed=$BASELINE_SPEED \
                --coverageMultiplier=$BASELINE_COVERAGE" \
                > /tmp/sim.log 2>&1

            # Extract and append result
            if grep -q "Throughput:" /tmp/sim.log; then
                # Parse metrics (extract only the first number on each line)
                throughput=$(grep "Throughput:" /tmp/sim.log | tail -1 | awk '{print $2}')
                delay=$(grep "Delay:" /tmp/sim.log | tail -1 | awk '{print $2}')
                pdr=$(grep "PDR:" /tmp/sim.log | tail -1 | awk '{print $2}' | sed 's/%//')
                drr=$(grep "DRR:" /tmp/sim.log | tail -1 | awk '{print $2}' | sed 's/%//')
                energy=$(grep "Energy:" /tmp/sim.log | tail -1 | awk '{print $2}')

                echo "$network,$algorithm,$nodes,$BASELINE_FLOWS,$BASELINE_PKT_RATE,$BASELINE_SPEED,$BASELINE_COVERAGE,$throughput,$delay,$pdr,$drr,$energy" \
                    >> "$csv"

                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC} (no output)"
            fi
        done
        echo ""

        # EXPERIMENT 2: Vary Number of Flows
        echo "  [EXP 2] Varying Number of Flows..."
        for flows in "${FLOWS[@]}"; do
            ((SIM_COUNT++))
            echo -ne "    [$SIM_COUNT/$TOTAL_SIMS] flows=$flows... "

            timeout 120 ./ns3 run \
                "scratch/cubic-comprehensive-eval \
                --networkType=$network \
                --algorithm=$algorithm \
                --numNodes=$BASELINE_NODES \
                --numFlows=$flows \
                --pktPerSec=$BASELINE_PKT_RATE \
                --nodeSpeed=$BASELINE_SPEED \
                --coverageMultiplier=$BASELINE_COVERAGE" \
                > /tmp/sim.log 2>&1

            if grep -q "Throughput:" /tmp/sim.log; then
                throughput=$(grep "Throughput:" /tmp/sim.log | tail -1 | awk '{print $NF}')
                delay=$(grep "Delay:" /tmp/sim.log | tail -1 | awk '{print $NF}')
                pdr=$(grep "PDR:" /tmp/sim.log | tail -1 | awk '{print $NF}' | sed 's/%//')
                drr=$(grep "DRR:" /tmp/sim.log | tail -1 | awk '{print $NF}' | sed 's/%//')
                energy=$(grep "Energy:" /tmp/sim.log | tail -1 | awk '{print $NF}')

                echo "$network,$algorithm,$BASELINE_NODES,$flows,$BASELINE_PKT_RATE,$BASELINE_SPEED,$BASELINE_COVERAGE,$throughput,$delay,$pdr,$drr,$energy" \
                    >> "$csv"

                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC} (no output)"
            fi
        done
        echo ""

        # EXPERIMENT 3: Vary Packet Rate
        echo "  [EXP 3] Varying Packet Rate..."
        for pkt_rate in "${PKT_RATES[@]}"; do
            ((SIM_COUNT++))
            echo -ne "    [$SIM_COUNT/$TOTAL_SIMS] pkt_rate=$pkt_rate... "

            timeout 120 ./ns3 run \
                "scratch/cubic-comprehensive-eval \
                --networkType=$network \
                --algorithm=$algorithm \
                --numNodes=$BASELINE_NODES \
                --numFlows=$BASELINE_FLOWS \
                --pktPerSec=$pkt_rate \
                --nodeSpeed=$BASELINE_SPEED \
                --coverageMultiplier=$BASELINE_COVERAGE" \
                > /tmp/sim.log 2>&1

            if grep -q "Throughput:" /tmp/sim.log; then
                throughput=$(grep "Throughput:" /tmp/sim.log | tail -1 | awk '{print $NF}')
                delay=$(grep "Delay:" /tmp/sim.log | tail -1 | awk '{print $NF}')
                pdr=$(grep "PDR:" /tmp/sim.log | tail -1 | awk '{print $NF}' | sed 's/%//')
                drr=$(grep "DRR:" /tmp/sim.log | tail -1 | awk '{print $NF}' | sed 's/%//')
                energy=$(grep "Energy:" /tmp/sim.log | tail -1 | awk '{print $NF}')

                echo "$network,$algorithm,$BASELINE_NODES,$BASELINE_FLOWS,$pkt_rate,$BASELINE_SPEED,$BASELINE_COVERAGE,$throughput,$delay,$pdr,$drr,$energy" \
                    >> "$csv"

                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC} (no output)"
            fi
        done
        echo ""

        # EXPERIMENT 4: Network-specific parameter
        if [ "$network" = "wireless" ]; then
            # EXPERIMENT 4: Vary Speed (Wireless)
            echo "  [EXP 4] Varying Node Speed (Wireless Mobile)..."
            for speed in "${SPEEDS[@]}"; do
                ((SIM_COUNT++))
                echo -ne "    [$SIM_COUNT/$TOTAL_SIMS] speed=${speed}m/s... "

                timeout 120 ./ns3 run \
                    "scratch/cubic-comprehensive-eval \
                    --networkType=$network \
                    --algorithm=$algorithm \
                    --numNodes=$BASELINE_NODES \
                    --numFlows=$BASELINE_FLOWS \
                    --pktPerSec=$BASELINE_PKT_RATE \
                    --nodeSpeed=$speed \
                    --coverageMultiplier=$BASELINE_COVERAGE" \
                    > /tmp/sim.log 2>&1

                if grep -q "Throughput:" /tmp/sim.log; then
                    throughput=$(grep "Throughput:" /tmp/sim.log | tail -1 | awk '{print $NF}')
                    delay=$(grep "Delay:" /tmp/sim.log | tail -1 | awk '{print $NF}')
                    pdr=$(grep "PDR:" /tmp/sim.log | tail -1 | awk '{print $NF}' | sed 's/%//')
                    drr=$(grep "DRR:" /tmp/sim.log | tail -1 | awk '{print $NF}' | sed 's/%//')
                    energy=$(grep "Energy:" /tmp/sim.log | tail -1 | awk '{print $NF}')

                    echo "$network,$algorithm,$BASELINE_NODES,$BASELINE_FLOWS,$BASELINE_PKT_RATE,$speed,$BASELINE_COVERAGE,$throughput,$delay,$pdr,$drr,$energy" \
                        >> "$csv"

                    echo -e "${GREEN}✓${NC}"
                else
                    echo -e "${RED}✗${NC} (no output)"
                fi
            done
            echo ""
        else
            # EXPERIMENT 4: Vary Coverage (Wired)
            echo "  [EXP 4] Varying Coverage Area (Wired Static)..."
            for coverage in "${COVERAGE[@]}"; do
                ((SIM_COUNT++))
                echo -ne "    [$SIM_COUNT/$TOTAL_SIMS] coverage=${coverage}x... "

                timeout 120 ./ns3 run \
                    "scratch/cubic-comprehensive-eval \
                    --networkType=$network \
                    --algorithm=$algorithm \
                    --numNodes=$BASELINE_NODES \
                    --numFlows=$BASELINE_FLOWS \
                    --pktPerSec=$BASELINE_PKT_RATE \
                    --nodeSpeed=$BASELINE_SPEED \
                    --coverageMultiplier=$coverage" \
                    > /tmp/sim.log 2>&1

                if grep -q "Throughput:" /tmp/sim.log; then
                    throughput=$(grep "Throughput:" /tmp/sim.log | tail -1 | awk '{print $NF}')
                    delay=$(grep "Delay:" /tmp/sim.log | tail -1 | awk '{print $NF}')
                    pdr=$(grep "PDR:" /tmp/sim.log | tail -1 | awk '{print $NF}' | sed 's/%//')
                    drr=$(grep "DRR:" /tmp/sim.log | tail -1 | awk '{print $NF}' | sed 's/%//')
                    energy=$(grep "Energy:" /tmp/sim.log | tail -1 | awk '{print $NF}')

                    echo "$network,$algorithm,$BASELINE_NODES,$BASELINE_FLOWS,$BASELINE_PKT_RATE,$BASELINE_SPEED,$coverage,$throughput,$delay,$pdr,$drr,$energy" \
                        >> "$csv"

                    echo -e "${GREEN}✓${NC}"
                else
                    echo -e "${RED}✗${NC} (no output)"
                fi
            done
            echo ""
        fi

    done
done

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                     RESULTS SUMMARY                           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}Output Directory:${NC} $RESULTS_DIR"
echo ""
echo -e "${GREEN}Generated CSV Files:${NC}"
for network in "${NETWORKS[@]}"; do
    for algorithm in "${ALGORITHMS[@]}"; do
        csv="${RESULTS_DIR}/${network}_${algorithm}_comprehensive.csv"
        if [ -f "$csv" ]; then
            lines=$(tail -n +2 "$csv" | wc -l)
            size=$(ls -lh "$csv" | awk '{print $5}')
            printf "  %-40s %4d lines  %6s\n" "$network - $algorithm:" "$lines" "$size"
        fi
    done
done

echo ""
echo -e "${GREEN}✓ Parameter sweep complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Analyze CSV results in Python/R:"
echo "     → Compare tcp-cubic vs tcp-cubic-rtt-aware"
echo "     → Plot performance metrics"
echo "     → Statistical analysis"
echo "  2. Generate report with findings"
echo "  3. Document insights on parameter impact"
echo ""

