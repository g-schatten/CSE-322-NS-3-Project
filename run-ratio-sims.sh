#!/usr/bin/env bash
# run-ratio-sims.sh
# Launches all 10 (link speed × RTT) combinations in parallel.
# Each simulation writes its output to ratio_${link}mbps_${rtt}ms.dat
#
# Usage:
#   chmod +x run-ratio-sims.sh
#   ./run-ratio-sims.sh
#
# Each run takes roughly:
#   ~5 min  at  20 Mbps
#   ~25 min at 100 Mbps
#   ~75 min at 300 Mbps
#  ~125 min at 500 Mbps
#  ~250 min at 1000 Mbps
# Running all 10 in parallel, total wall-clock ≈ time of the 1000 Mbps run.

set -e
cd "$(dirname "$0")"

LINK_SPEEDS=(20 100 300 500 1000)
RTT_VALUES=(20 100)   # ms: 20=short RTT, 100=long RTT

PIDS=()
LABELS=()

for link in "${LINK_SPEEDS[@]}"; do
  for rtt in "${RTT_VALUES[@]}"; do
    outfile="ratio_${link}mbps_${rtt}ms.dat"
    errfile="ratio_${link}mbps_${rtt}ms_err.txt"
    echo "Starting: linkMbps=${link}, rttMs=${rtt}  → ${outfile}"
    ./ns3 run scratch/test-cubic-ratio -- --linkMbps=${link} --rttMs=${rtt} \
        > "${outfile}" 2> "${errfile}" &
    PIDS+=($!)
    LABELS+=("${link}Mbps/${rtt}ms")
    # Small stagger to avoid cmake lock contention
    sleep 3
  done
done

echo ""
echo "All ${#PIDS[@]} simulations running in parallel."
echo "Monitor with:  tail -5 ratio_*mbps_*.dat"
echo ""

# Wait for all and report
FAILED=0
for i in "${!PIDS[@]}"; do
  pid=${PIDS[$i]}
  label=${LABELS[$i]}
  if wait "$pid"; then
    echo "  DONE:   ${label}"
  else
    echo "  FAILED: ${label}  (check ratio_${label/\//_}_err.txt)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
if [[ $FAILED -eq 0 ]]; then
  echo "All simulations complete. Run:"
  echo "  .venv/bin/python3 plot-ratio.py"
else
  echo "${FAILED} simulation(s) failed. Check the *_err.txt files."
fi
