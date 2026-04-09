#!/bin/bash

echo "Testing parameter sweep with minimal sample..."
echo ""

mkdir -p parameter_sweep_results

# Initialize test CSV
csv="parameter_sweep_results/wired_cubic_test.csv"
echo "Network,Algorithm,NumNodes,NumFlows,PktPerSec,NodeSpeed,CoverageMultiplier,Throughput_Mbps,Delay_ms,PDR_percent,DRR_percent,Energy_J" > "$csv"

# Run 3 test simulations
for nodes in 20 40 60; do
    echo "Testing: nodes=$nodes..."
    
    timeout 60 ./ns3 run \
        "scratch/cubic-comprehensive-eval \
        --networkType=wired \
        --algorithm=cubic \
        --numNodes=$nodes \
        --numFlows=20 \
        --pktPerSec=200 \
        --nodeSpeed=10 \
        --coverageMultiplier=2" \
        > /tmp/test_sim.log 2>&1
    
    # Extract metrics using sed for robustness
    if grep -q "Throughput:" /tmp/test_sim.log; then
        throughput=$(grep "Throughput:" /tmp/test_sim.log | tail -1 | sed 's/.*: \([^ ]*\).*/\1/')
        delay=$(grep "Delay:" /tmp/test_sim.log | tail -1 | sed 's/.*: \([^ ]*\).*/\1/')
        pdr=$(grep "PDR:" /tmp/test_sim.log | tail -1 | sed 's/.*: \([^%]*\)%.*/\1/')
        drr=$(grep "DRR:" /tmp/test_sim.log | tail -1 | sed 's/.*: \([^%]*\)%.*/\1/')
        energy=$(grep "Energy:" /tmp/test_sim.log | tail -1 | sed 's/.*: \([^ ]*\).*/\1/')
        
        echo "wired,cubic,$nodes,20,200,10,2,$throughput,$delay,$pdr,$drr,$energy" >> "$csv"
        echo "  ✓ Captured metrics: tput=$throughput, delay=$delay, pdr=$pdr"
    fi
done

echo ""
echo "CSV Output:"
cat "$csv"
echo ""
echo "✓ Test complete!"
