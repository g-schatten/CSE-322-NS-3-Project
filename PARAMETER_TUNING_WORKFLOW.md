PARAMETER TUNING COMPLETE WORKFLOW
═════════════════════════════════════════════════════════════════════════════════

You now have:
✓ RTT-Trend-Aware CUBIC implementation (tcp-cubic-rtt-aware.h/cc)
✓ Configurable parameters (K, Alpha, GammaMin, GammaMax)
✓ Comparison simulation (test-cubic-comparison.cc)
✓ Automated plotting (plot-rtt-comparison.py)
✓ Tuning guides (TUNING_GUIDE.md, QUICK_TUNING.sh)

═════════════════════════════════════════════════════════════════════════════════
STEP-BY-STEP: HOW TO TWEAK AND OBSERVE IMPROVEMENTS
═════════════════════════════════════════════════════════════════════════════════

STEP 1: ESTABLISH BASELINE (K=0.5, Alpha=0.125, GammaMin=0.5, GammaMax=1.5)
──────────────────────────────────────────────────────────────────────────────
Command:
  ./ns3 run scratch/test-cubic-comparison > comparison_baseline.dat
  .venv/bin/python3 plot-rtt-comparison.py

Output files:
  comparison-cwnd-single.png    ← Compare Original CUBIC-1 vs RTT-Aware CUBIC-1
  comparison-cwnd-all.png       ← See all 4 flows
  comparison-rtt-gamma.png      ← RTT and gamma evolution

Console output (important metrics):
  Flow 1 (Original ): mean=185.7 pkts, max=312.5 pkts, std=39.8 pkts
  Flow 3 (RTT-Aware): mean=138.2 pkts, max=284.7 pkts, std=34.8 pkts
  Flow 3: mean γ=1.000, min=1.000, max=1.000  ← Currently all 1.0 (not adjusting)

OBSERVATION: Default RTT-Aware is TOO CONSERVATIVE (gamma stuck at 1.0).
             RTT isn't varying enough, so adjustment not kicking in.


STEP 2: MAKE IT MORE RESPONSIVE (Increase K or lower Alpha)
──────────────────────────────────────────────────────────

Option A: Increase K from 0.5 → 1.0 (more aggressive gamma adjustment)
  Command:
    ./ns3 run scratch/test-cubic-comparison -- --K=1.0 > comparison_K1.0.dat
    .venv/bin/python3 plot-rtt-comparison.py

  Expected change:
    γ should vary more (not stuck at 1.0)
    Flow 3 mean CWND might decrease further (more throttling)
    Look for: γ values showing 0.9-1.1 range instead of all 1.0


Option B: Lower Alpha from 0.125 → 0.0625 (cleaner RTT signal)
  Command:
    ./ns3 run scratch/test-cubic-comparison -- --Alpha=0.0625 > comparison_alpha0.0625.dat
    .venv/bin/python3 plot-rtt-comparison.py

  Expected change:
    RTT estimate smoother (less jitter in top subplot)
    More stable gamma pattern
    Might see better separation from Original CUBIC


STEP 3: OBSERVE SPECIFIC METRICS
──────────────────────────────────

In comparison-rtt-gamma.png:

  Top subplot (RTT evolution):
  ✓ Look for: RTT line that VARIES (oscillates up/down)
  ✗ Bad sign: Flat line at 100ms (no RTT variation detected)

  Bottom subplot (Gamma evolution):
  ✓ Look for: γ line that VARIES around 1.0
  ✗ Bad sign: Flat line at γ=1.0 (adjustment not active)
  ✓ Good pattern: When RTT goes up (top), γ goes down (bottom)
                   When RTT goes down (top), γ goes up (bottom)

In comparison-cwnd-single.png:
  ✓ Look for: RTT-Aware curve (green dashed) DIFFERENT from Original (red solid)
  ✓ Good sign: Green curve smoother or lower peaks (better congestion response)
  ✗ Bad sign: Green and red overlap completely (adjustment not working)

Console statistics:
  Compare "mean" CWND:
    If (Original - RTT-Aware) > 30 pkts: Good responsiveness
    If (Original - RTT-Aware) ≈ 0 pkts:  Not adjusting enough

  Check Gamma statistics:
    If mean γ ≈ 1.0 AND min=1.0 AND max=1.0: Increase K or decrease Alpha
    If values vary (e.g., 0.9-1.1): Perfect! Adjustment is working


STEP 4: ITERATE - FIND YOUR "SWEET SPOT"
──────────────────────────────────────────

If gamma is STILL all 1.0:
  ✓ Try: --K=1.5 --Alpha=0.0625
    Command: ./ns3 run scratch/test-cubic-comparison -- --K=1.5 --Alpha=0.0625

  ✓ Or: --K=2.0
    Command: ./ns3 run scratch/test-cubic-comparison -- --K=2.0

  ⚠️  LIMIT: Don't go above K≈2.5, will cause oscillations


If gamma oscillates between extremes (0.5 and 1.5):
  ✓ Reduce K: --K=0.3
  ✓ Increase Alpha: --Alpha=0.25
  ✓ Narrow bounds: --GammaMin=0.7 --GammaMax=1.3

  Command: ./ns3 run scratch/test-cubic-comparison -- --K=0.3 --GammaMin=0.7 --GammaMax=1.3


If RTT-Aware and Original CWND are TOO different (unfair):
  ✓ Raise GammaMin: --GammaMin=0.7 (prevents too much slowdown)
  ✓ Lower K: --K=0.25 (reduce sensitivity)

  Command: ./ns3 run scratch/test-cubic-comparison -- --K=0.25 --GammaMin=0.75


═════════════════════════════════════════════════════════════════════════════════
BATCH TESTING: Run Multiple Parameter Sets
═════════════════════════════════════════════════════════════════════════════════

Create a test script (simple loop):

  for k in 0.25 0.5 1.0 1.5; do
    for alpha in 0.0625 0.125 0.25; do
      echo "Testing K=$k Alpha=$alpha"
      mkdir -p results_K${k}_A${alpha}
      ./ns3 run scratch/test-cubic-comparison -- --K=$k --Alpha=$alpha > results_K${k}_A${alpha}/comparison.dat
      cd results_K${k}_A${alpha}
      .venv/bin/python3 ../plot-rtt-comparison.py > /dev/null 2>&1
      cd ..
      echo "✓ Done: results_K${k}_A${alpha}/"
    done
  done

Or use the automated script:
  ./run-parameter-sweep.py --k 0.25 0.5 1.0 1.5 --alpha 0.0625 0.125 0.25


═════════════════════════════════════════════════════════════════════════════════
IMPORTANT: THINGS TO KEEP IN MIND WHEN TWEAKING
═════════════════════════════════════════════════════════════════════════════════

1. ALWAYS CHANGE ONE PARAMETER AT A TIME
   ✓ DO: Run with K=1.0 (all others default)
   ✗ DON'T: Change K, Alpha, and GammaMin all at once
   → Can't isolate which parameter caused the change

2. SAVE OUTPUTS FROM EACH EXPERIMENT
   Save before running next: mv comparison-*.png results_K1.0/
   → Compare side-by-side later

3. DON'T EXPECT HUGE DIFFERENCES
   Original: mean=185.7 pkts
   RTT-Aware: mean=138.2 pkts
   → This is NORMAL and EXPECTED ($3 is a different flow competing)
   → Look for PATTERNS (gamma varying, RTT correlated), not huge CWND drops

4. GAMMA = 1.0 IS OK SOMETIMES
   When network is not congested (RTT flat), gamma=1.0 is correct
   → Only adjust when RTT is actually changing

5. STABILITY > THROUGHPUT
   Smooth curves > jagged curves
   Lower std dev > higher std dev
   Consistent fairness > occasional big differences

6. THE HOLY TRINITY FOR GOOD TUNING:
   ✓ Gamma varies (not all 1.0)
   ✓ Gamma correlates with RTT (when RTT up, gamma down)
   ✓ CWND more stable (lower std dev than Original CUBIC)

7. BEWARE OF OVER-TUNING
   "More adjustment" doesn't always mean "better"
   Conservative (K=0.25) might outperform aggressive (K=2.0)
   → Your specific network characteristics matter

8. TEST IN YOUR TARGET SCENARIO
   These defaults designed for:
     50 Mbps bottleneck, 100ms RTT, RED+ECN queue, 4 flows
   If your use case is different, tuning will need to change:
     - High-speed networks (100+ Mbps) → Try lower Alpha
     - Variable RTT → Try higher K
     - Bursty traffic → Try narrower gamma bounds

═════════════════════════════════════════════════════════════════════════════════
QUICK DECISION TREE: What Should I Change?
═════════════════════════════════════════════════════════════════════════════════

START: Run baseline and generate plots
  ↓
Do gamma values vary (not all 1.0)?
  ├→ NO (all 1.0):
  │  Try:  --K=1.0 --Alpha=0.0625
  │  If still no: --K=1.5 or --Alpha=0.0625
  │
  └→ YES (varies):
     ↓
     Is gamma correlated with RTT (when RTT ↑, gamma ↓)?
       ├→ NO (random):
       │  Increase Alpha: --Alpha=0.25
       │
       └→ YES (correlated):
          ✓ GOOD! Check CWND statistics
            ↓
            Is RTT-Aware CWND < Original CWND?
              ├→ NO (too similar):
              │  Increase K: --K=1.0
              │
              └→ YES (different):
                 ✓ CHECK! Is it stable?
                    ├→ Oscillating:  Increase Alpha or narrow bounds
                    └→ Smooth:       ✓ OPTIMAL! Keep these settings

═════════════════════════════════════════════════════════════════════════════════

Ready to start tuning? See QUICK_TUNING.sh for copy-paste commands!
