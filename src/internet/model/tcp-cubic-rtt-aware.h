// tcp-cubic-rtt-aware.h
// RTT-Trend-Aware Extension to CUBIC TCP
//
// Extends the base CUBIC implementation with RTT-based window growth adjustment.
// Core modification: W_modified(t) = γ · W_cubic(t) where γ adjusts based on RTT trend.
//
// Key features:
// - RTT smoothing via EWMA (α = 0.125)
// - Trend detection: compare current RTT vs baseline (minimum seen)
// - Gamma calculation: γ = 1 / (1 + k · (rtt_ratio - 1))
// - Safe clamping: 0.5 ≤ γ ≤ 1.5
//
// What changes: Only congestion avoidance window growth
// What stays: Loss response (β=0.8), slow start, TCP-friendly region

#ifndef TCP_CUBIC_RTT_AWARE_H
#define TCP_CUBIC_RTT_AWARE_H

#include "tcp-cubic-custom.h"
#include "ns3/data-rate.h"

namespace ns3 {

class TcpCubicRttAware : public TcpCubicCustom
{
public:
  static TypeId GetTypeId ();

  TcpCubicRttAware ();
  TcpCubicRttAware (const TcpCubicRttAware& sock);
  ~TcpCubicRttAware () override;

  virtual Ptr<TcpCongestionOps> Fork () override;

  // RTT measurement override
  virtual void PktsAcked (Ptr<TcpSocketState> tcb, uint32_t packetsAcked,
                          const Time& rtt) override;

protected:
  // Override window increase to apply gamma adjustment
  virtual void IncreaseWindow (Ptr<TcpSocketState> tcb, uint32_t segmentsAcked) override;

  // Override congestion state changes to reset baseline
  virtual void CongestionStateSet (Ptr<TcpSocketState> tcb,
                                   const TcpSocketState::TcpCongState_t newState) override;

private:
  /**
   * Calculate gamma (growth adjustment factor) based on RTT trend
   * \return gamma value (clamped to [m_gammaMin, m_gammaMax])
   */
  double CalculateGamma () const;

  /**
   * Update RTT baseline (minimum RTT seen or at epoch start)
   */
  void UpdateRttBaseline ();

  // ── RTT tracking ───────────────────────────────────────────────────
  Time     m_rttSmooth;        //!< EWMA-smoothed RTT
  Time     m_rttBaseline;      //!< Baseline RTT for trend comparison
  Time     m_minRtt;           //!< Minimum RTT observed (persistent)
  bool     m_rttInitialized;   //!< Whether we have valid RTT samples

  // ── EWMA parameters ────────────────────────────────────────────────
  double   m_alpha;            //!< EWMA weight (0.125 = 1/8, like TCP RTT estimation)

  // ── Gamma parameters ───────────────────────────────────────────────
  double   m_k;                //!< Sensitivity parameter for gamma calculation
  double   m_gammaMin;         //!< Minimum allowed gamma (default 0.5)
  double   m_gammaMax;         //!< Maximum allowed gamma (default 1.5)
  double   m_rttThresholdUp;   //!< RTT ratio threshold for "increasing" (default 1.1)
  double   m_rttThresholdDown; //!< RTT ratio threshold for "decreasing" (default 0.9)

  // ── Statistics (for logging/debugging) ─────────────────────────────
  double   m_lastGamma;        //!< Most recently calculated gamma
};

} // namespace ns3

#endif /* TCP_CUBIC_RTT_AWARE_H */
