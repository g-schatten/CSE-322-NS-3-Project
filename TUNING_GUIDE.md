"""
PARAMETER TUNING GUIDE: RTT-Trend-Aware CUBIC

Key Attributes and Their Effects:
═════════════════════════════════════════════════════════════════════════════════

1. ALPHA (RTT Smoothing Weight)
   ──────────────────────────────
   Default: 0.125 (1/8, matches TCP RTT estimation)
   Range: 0.01 – 0.5

   Effect:
   - Higher α: Responds faster to RTT changes (more sensitive)
   - Lower α: Smoother RTT estimate (less jittery)

   What to observe:
   - Gamma oscillation frequency in comparison-rtt-gamma.png
   - Window growth smoothness in comparison-cwnd-*.png

   Tuning strategy:
   - α = 0.25   → More aggressive response to congestion
   - α = 0.0625 → More conservative, less reactive

   ⚠️  WARNING: Very high α (>0.3) can cause instability and oscillations


2. K (Sensitivity Parameter)
   ──────────────────────────
   Default: 0.5
   Range: 0.1 – 2.0

   Effect:
   γ = 1 / (1 + k·(rtt_ratio - 1))

   - Higher k: Larger γ adjustments per unit RTT change
   - Lower k: Smaller γ adjustments (more conservative)

   Examples:
   - If rtt_ratio = 1.1 (10% RTT increase):
     k=0.5   → γ = 1 / (1 + 0.5×0.1) = 0.952  (5% slowdown)
     k=1.0   → γ = 1 / (1 + 1.0×0.1) = 0.909  (9% slowdown)
     k=2.0   → γ = 1 / (1 + 2.0×0.1) = 0.833  (17% slowdown)

   What to observe:
   - Mean CWND difference between Original and RTT-Aware
   - Gamma range (min/max values)
   - Fairness (compare mean CWNDs in stats)

   Tuning strategy:
   - k = 1.0   → More aggressive response
   - k = 0.25  → Gentler response, closer to original CUBIC


3. GAMMA_MIN / GAMMA_MAX (Clamps)
   ──────────────────────────────
   Default: GammaMin=0.5, GammaMax=1.5

   Safe range: [0.3 – 2.0]
   Recommended: [0.5 – 1.5]

   Effect:
   - GammaMin: Prevents window from shrinking too fast
   - GammaMax: Prevents overly aggressive growth

   ⚠️  CRITICAL: NEVER set GammaMin < 0.3 or GammaMax > 2.0
       → Risk of congestion collapse or RTO storms

   Conservative:     GammaMin=0.7, GammaMax=1.3  (narrow band)
   Moderate:         GammaMin=0.5, GammaMax=1.5  (default)
   Aggressive:       GammaMin=0.3, GammaMax=2.0  (wide band)


4. RTT_THRESHOLD_UP / RTT_THRESHOLD_DOWN
   ─────────────────────────────────────
   Default: ThresholdUp=1.1, ThresholdDown=0.9

   Effect:
   - ThresholdUp: Fraction at which RTT is considered "increasing"
   - ThresholdDown: Fraction at which RTT is considered "decreasing"

   Current behavior (see tcp-cubic-rtt-aware.cc):
   - If rtt_ratio > 1.1: RTT increasing
   - If rtt_ratio < 0.9: RTT decreasing
   - Otherwise: rtt_ratio = 1.0 (neutral)

   ⚠️  These are currently NOT used in the implementation
       (set to 1.0 neutral by default). Future enhancement: implement
       multi-level response based on these thresholds.


═════════════════════════════════════════════════════════════════════════════════
OBSERVATION METRICS (from plot output)
═════════════════════════════════════════════════════════════════════════════════

1. From Steady-State Statistics (t > 20s):

   Mean CWND:
   - Original CUBIC-1: 185.7 pkts
   - RTT-Aware   CUBIC-1: 138.2 pkts
   - Difference: -25% (slower growth in response to RTT)

   What it means:
   - Negative difference (RTT-Aware < Original) → Better congestion response
   - Positive difference → Over-aggressive RTT adjustment

   Standard Deviation (Stability):
   - Lower std dev → More stable window growth
   - Higher std dev → More oscillation


2. From comparison-rtt-gamma.png:

   RTT Evolution:
   - Should show RTT increase/decrease patterns
   - Watch for sudden jumps (packet loss events)

   Gamma Evolution:
   - Should vary between 0.5 and 1.5 (or your clamps)
   - Correlation with RTT: γ < 1 when RTT increases

   Mean Gamma (from stats):
   - Should NOT be exactly 1.0 (means adjustment not active)
   - Should vary based on network congestion


3. Fairness (Max CWND):

   Original CUBIC-1: 312.5 pkts
   RTT-Aware CUBIC-1: 284.7 pkts
   - Similar peaks acceptable (shows fairness maintained)


═════════════════════════════════════════════════════════════════════════════════
TUNING STRATEGY & BEST PRACTICES
═════════════════════════════════════════════════════════════════════════════════

Step 1: Establish Baseline
   └─ Run with defaults, save comparison-*.png
      → Baseline for measuring improvements


Step 2: Vary One Parameter at a Time
   └─ Change only α, K, or gamma bounds
   └─ Keep others constant
   └─ Run simulation and compare


Step 3: Look for Improvements in This Order
   ✓ STABILITY (lower std dev is good)
   ✓ FAIRNESS (similar mean CWNDs across flows)
   ✓ RESPONSIVENESS (γ varies, not stuck at 1.0)
   ✓ THROUGHPUT (optional, depends on use case)


Step 4: Monitor for Problems
   ✗ Oscillations (jagged cwnd) → Reduce K or α
   ✗ Unfairness (very different means) → Adjust gamma bounds
   ✗ Gamma always 1.0 → Not detecting RTT changes (check RTT data)
   ✗ Sharp drops → gamma too aggressive (reduce K or GammaMin)


═════════════════════════════════════════════════════════════════════════════════
COMMON TUNING SCENARIOS
═════════════════════════════════════════════════════════════════════════════════

Scenario: "RTT-Aware is too conservative (still using 90% of original CUBIC)"
──────────────────────────────────────────────────────────────────────────
Problem: Gamma not deviating much from 1.0
Solution:
  1. Increase K from 0.5 → 1.0 or 1.5
  2. Decrease Alpha from 0.125 → 0.0625 (smoother RTT, clearer trends)
  3. Check RTT data: does it actually show variation?

Example:
   Config::SetDefault("ns3::TcpCubicRttAware::K", DoubleValue(1.0));
   Config::SetDefault("ns3::TcpCubicRttAware::Alpha", DoubleValue(0.0625));


Scenario: "RTT-Aware is too aggressive (cwnd oscillates wildly)"
──────────────────────────────────────────────────────────────
Problem: Gamma swings too much, gamma bounces between 0.5 and 1.5
Solution:
  1. Decrease K from 0.5 → 0.2 or 0.3
  2. Narrow gamma bounds: GammaMin=0.7, GammaMax=1.3
  3. Increase Alpha to smooth out noise

Example:
   Config::SetDefault("ns3::TcpCubicRttAware::K", DoubleValue(0.25));
   Config::SetDefault("ns3::TcpCubicRttAware::GammaMin", DoubleValue(0.7));
   Config::SetDefault("ns3::TcpCubicRttAware::GammaMax", DoubleValue(1.3));


Scenario: "Original and RTT-Aware are too different (unfair)"
──────────────────────────────────────────────────────────────
Problem: Original CUBIC mean=200 pkts, RTT-Aware mean=120 pkts
Solution:
  1. Raise GammaMin from 0.5 → 0.7 or 0.8 (prevent too much slowdown)
  2. Decrease K to reduce sensitivity
  3. Use higher Alpha for cleaner RTT estimates

Example:
   Config::SetDefault("ns3::TcpCubicRttAware::GammaMin", DoubleValue(0.75));
   Config::SetDefault("ns3::TcpCubicRttAware::K", DoubleValue(0.3));


═════════════════════════════════════════════════════════════════════════════════
QUICK EXPERIMENT CHECKLIST
═════════════════════════════════════════════════════════════════════════════════

Before each run:
 ☐ Edit Config::SetDefault() calls (see examples below)
 ☐ Rebuild: ./ns3 build scratch/test-cubic-comparison
 ☐ Clear old data: rm comparison.dat
 ☐ Run: ./ns3 run scratch/test-cubic-comparison > comparison.dat
 ☐ Plot: .venv/bin/python3 plot-rtt-comparison.py
 ☐ Save outputs: mv comparison-*.png comparison_exp_K1.0_alpha0.25/

View metrics:
 ☐ Check "Steady-State Statistics" in terminal output
 ☐ Compare mean CWND between flows 1 and 3
 ☐ Check "Gamma Statistics" for variation
 ☐ Visually inspect comparison-rtt-gamma.png for correlation

═════════════════════════════════════════════════════════════════════════════════
"""
