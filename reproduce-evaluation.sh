#!/bin/bash
# reproduce-evaluation.sh
#
# Single executable script to reproduce all evaluation results for RTT-Aware CUBIC
# Generates all plots and metrics needed for final presentation
#
# Usage: ./reproduce-evaluation.sh
#
# Output:
#   - comparison.dat (raw simulation data)
#   - comparison-cwnd-single.png (main comparison plot)
#   - comparison-cwnd-all.png (all flows comparison)
#   - comparison-rtt-gamma.png (RTT and gamma evolution)
#   - Console output with statistics
#

set -e  # Exit immediately on error

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COLOR_HEADER='\033[1;36m'    # Cyan bold
COLOR_SUCCESS='\033[0;32m'   # Green
COLOR_ERROR='\033[0;31m'     # Red
COLOR_RESET='\033[0m'        # Reset

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

print_header() {
    echo -e "${COLOR_HEADER}$1${COLOR_RESET}"
}

print_success() {
    echo -e "${COLOR_SUCCESS}✓ $1${COLOR_RESET}"
}

print_error() {
    echo -e "${COLOR_ERROR}✗ $1${COLOR_RESET}"
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: VERIFY ENVIRONMENT
# ═══════════════════════════════════════════════════════════════════════════════

print_header "╔════════════════════════════════════════════════════════════════╗"
print_header "║  RTT-Trend-Aware CUBIC - Full Evaluation Reproduction         ║"
print_header "║  This script regenerates all results from the base paper       ║"
print_header "╚════════════════════════════════════════════════════════════════╝"
echo ""

print_header "[STEP 1] Verifying environment..."
echo ""

# Check for ns3 executable
if [ ! -f "./ns3" ]; then
    print_error "ns3 executable not found in $SCRIPT_DIR"
fi
print_success "ns-3 framework found"

# Check for Python environment
if [ ! -f ".venv/bin/python3" ]; then
    print_error "Python venv not found (.venv/bin/python3)"
fi
print_success "Python venv found"

# Check for plot script
if [ ! -f "plot-rtt-comparison.py" ]; then
    print_error "plot-rtt-comparison.py not found"
fi
print_success "Plot script found"

# Check for implementation files
if [ ! -f "src/internet/model/tcp-cubic-rtt-aware.h" ]; then
    print_error "RTT-Aware CUBIC implementation not found"
fi
print_success "RTT-Aware CUBIC implementation found"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: BUILD SIMULATION
# ═══════════════════════════════════════════════════════════════════════════════

print_header "[STEP 2] Building ns-3 simulation (test-cubic-comparison)..."
echo ""

# Clean old build artifacts (optional, speeds up first-time build)
# rm -rf build/scratch/CMakeFiles/scratch_test-cubic-comparison* 2>/dev/null || true

# Build the target
if ! ./ns3 build scratch/test-cubic-comparison > /dev/null 2>&1; then
    print_error "Build failed. Please check ns3 installation."
fi
print_success "Build complete"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: RUN SIMULATION
# ═══════════════════════════════════════════════════════════════════════════════

print_header "[STEP 3] Running simulation..."
echo ""
echo "  Topology: Single bottleneck (50 Mbps, 100ms RTT)"
echo "  Flows: 2 Original CUBIC + 2 RTT-Aware CUBIC"
echo "  Duration: 60 seconds"
echo "  Queue: RED + ECN"
echo ""
echo "  Running..."

# Remove old data file to ensure fresh results
rm -f comparison.dat

# Run simulation with default parameters
if ! ./ns3 run scratch/test-cubic-comparison > comparison.dat 2>&1; then
    print_error "Simulation failed"
fi

print_success "Simulation complete"
echo ""

# Count data points
LINE_COUNT=$(wc -l < comparison.dat)
echo "  Data points collected: $LINE_COUNT samples"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: EXTRACT AND DISPLAY STATISTICS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "[STEP 4] Computing statistics from simulation data..."
echo ""

# Extract statistics from simulation output
echo "  Analyzing CWND evolution (steady-state t > 20s)..."

# Use Python to compute statistics
.venv/bin/python3 << 'PYTHON_STATS'
import numpy as np

# Parse comparison.dat
flows = {1: [], 2: [], 3: [], 4: []}
with open('comparison.dat', 'r') as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) >= 3:
            try:
                flow_id = int(parts[0])
                time = float(parts[1])
                cwnd = int(parts[2])

                # Only steady-state (t > 20s)
                if time > 20.0 and flow_id in flows:
                    flows[flow_id].append(cwnd)
            except:
                pass

# Compute statistics
print("─" * 70)
print("Steady-State Statistics (t > 20s)")
print("─" * 70)
print()

for flow_id in [1, 2, 3, 4]:
    if flows[flow_id]:
        data = np.array(flows[flow_id])
        flow_type = "Original CUBIC" if flow_id in [1, 2] else "RTT-Aware"

        print(f"Flow {flow_id} ({flow_type:15s}): "
              f"mean={np.mean(data):6.1f} pkts, "
              f"max={np.max(data):6.1f} pkts, "
              f"std={np.std(data):6.1f} pkts")

print()
print("─" * 70)

# Summary comparison
if flows[1] and flows[3]:
    orig = np.mean(np.array(flows[1]))
    rtta = np.mean(np.array(flows[3]))
    diff_pct = 100 * (rtta - orig) / orig

    print()
    print("RTT-Aware vs Original CUBIC:")
    print(f"  Mean CWND difference: {rtta:.1f} - {orig:.1f} = {diff_pct:+.1f}%")
    print()

PYTHON_STATS

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: GENERATE PLOTS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "[STEP 5] Generating comparison plots..."
echo ""

if ! .venv/bin/python3 plot-rtt-comparison.py > /dev/null 2>&1; then
    print_error "Plot generation failed"
fi

# Verify plots were created
PLOTS=(
    "comparison-cwnd-single.png"
    "comparison-cwnd-all.png"
    "comparison-rtt-gamma.png"
)

for plot in "${PLOTS[@]}"; do
    if [ -f "$plot" ]; then
        SIZE=$(ls -lh "$plot" | awk '{print $5}')
        print_success "$plot ($SIZE)"
    else
        print_error "Failed to generate $plot"
    fi
done

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

print_header "[STEP 6] Evaluation ready!"
echo ""

print_success "All simulations and plots generated successfully"
echo ""

print_header "Next steps for evaluation:"
echo ""
echo "  1. Review plots:"
echo "     • comparison-cwnd-single.png   → Main comparison (Original vs RTT-Aware)"
echo "     • comparison-cwnd-all.png      → All 4 flows (fairness check)"
echo "     • comparison-rtt-gamma.png     → RTT trend and gamma adjustment"
echo ""
echo "  2. Read documentation:"
echo "     • EVALUATION_REPORT.tex        → Full technical report"
echo "     • TUNING_GUIDE.md              → Parameter explanations"
echo "     • PARAMETER_TUNING_WORKFLOW.md → How to understand the results"
echo ""
echo "  3. Generate PDF report:"
echo "     $ pdflatex EVALUATION_REPORT.tex"
echo "     $ pdflatex EVALUATION_REPORT.tex  # (run twice for TOC)"
echo ""
echo "  4. Explore the implementation:"
echo "     • src/internet/model/tcp-cubic-rtt-aware.h   → Header"
echo "     • src/internet/model/tcp-cubic-rtt-aware.cc  → Implementation"
echo "     • scratch/test-cubic-comparison.cc           → Simulation setup"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY TABLE
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
print_header "═" "65"
print_header "Summary of Results"
print_header "═" "65"
echo ""

# Read and display the summary statistics
.venv/bin/python3 << 'PYTHON_SUMMARY'
import numpy as np

# Parse data file
flows = {1: [], 2: [], 3: [], 4: []}
with open('comparison.dat', 'r') as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) >= 3:
            try:
                flow_id = int(parts[0])
                time = float(parts[1])
                cwnd = int(parts[2])

                if time > 20.0 and flow_id in flows:
                    flows[flow_id].append(cwnd)
            except:
                pass

# Display summary table
print(f"{'Flow':<6} {'Type':<18} {'Mean (pkts)':<15} {'Max (pkts)':<15} {'Std (pkts)':<15}")
print("─" * 70)

for flow_id in [1, 2, 3, 4]:
    if flows[flow_id]:
        data = np.array(flows[flow_id])
        flow_type = "Original CUBIC" if flow_id in [1, 2] else "RTT-Aware"
        mean = np.mean(data)
        max_v = np.max(data)
        std = np.std(data)
        print(f"{flow_id:<6} {flow_type:<18} {mean:>14.1f} {max_v:>14.1f} {std:>14.1f}")

print()

# Compute improvement metrics
if flows[1] and flows[3]:
    orig_mean = np.mean(np.array(flows[1]))
    rtta_mean = np.mean(np.array(flows[3]))
    orig_std = np.std(np.array(flows[1]))
    rtta_std = np.std(np.array(flows[3]))

    cwnd_diff = 100 * (rtta_mean - orig_mean) / orig_mean
    std_diff = 100 * (rtta_std - orig_std) / orig_std

    print("Key Metrics:")
    print(f"  • Mean CWND difference:  {cwnd_diff:+.1f}% (RTT-Aware vs Original)")
    print(f"  • Stability improvement: {-std_diff:+.1f}% (lower std dev = better)")
    print()

PYTHON_SUMMARY

echo ""
print_header "═" "65"
echo ""

print_success "Evaluation reproduction complete!"
echo ""
echo "Ready for presentation. All plots and data are in this directory."
echo ""
