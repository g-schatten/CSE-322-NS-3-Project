// tcp-cubic-rtt-aware.cc
// RTT-Trend-Aware Extension to CUBIC TCP

#include "tcp-cubic-rtt-aware.h"
#include "ns3/log.h"
#include "ns3/simulator.h"
#include <algorithm>

namespace ns3 {

NS_LOG_COMPONENT_DEFINE ("TcpCubicRttAware");
NS_OBJECT_ENSURE_REGISTERED (TcpCubicRttAware);

TypeId
TcpCubicRttAware::GetTypeId ()
{
  static TypeId tid = TypeId ("ns3::TcpCubicRttAware")
    .SetParent<TcpCubicCustom> ()
    .SetGroupName ("Internet")
    .AddConstructor<TcpCubicRttAware> ()
    .AddAttribute ("Alpha",
                   "EWMA weight for RTT smoothing (0 < alpha < 1)",
                   DoubleValue (0.125),
                   MakeDoubleAccessor (&TcpCubicRttAware::m_alpha),
                   MakeDoubleChecker<double> (0.0, 1.0))
    .AddAttribute ("K",
                   "Sensitivity parameter for gamma calculation",
                   DoubleValue (0.5),
                   MakeDoubleAccessor (&TcpCubicRttAware::m_k),
                   MakeDoubleChecker<double> (0.0))
    .AddAttribute ("GammaMin",
                   "Minimum allowed gamma value",
                   DoubleValue (0.5),
                   MakeDoubleAccessor (&TcpCubicRttAware::m_gammaMin),
                   MakeDoubleChecker<double> (0.1, 1.0))
    .AddAttribute ("GammaMax",
                   "Maximum allowed gamma value",
                   DoubleValue (1.5),
                   MakeDoubleAccessor (&TcpCubicRttAware::m_gammaMax),
                   MakeDoubleChecker<double> (1.0, 5.0))
    .AddAttribute ("RttThresholdUp",
                   "RTT ratio threshold for 'increasing' trend",
                   DoubleValue (1.1),
                   MakeDoubleAccessor (&TcpCubicRttAware::m_rttThresholdUp),
                   MakeDoubleChecker<double> (1.0))
    .AddAttribute ("RttThresholdDown",
                   "RTT ratio threshold for 'decreasing' trend",
                   DoubleValue (0.9),
                   MakeDoubleAccessor (&TcpCubicRttAware::m_rttThresholdDown),
                   MakeDoubleChecker<double> (0.0, 1.0))
    ;
  return tid;
}

TcpCubicRttAware::TcpCubicRttAware ()
  : TcpCubicCustom (),
    m_rttSmooth (Time (0)),
    m_rttBaseline (Time::Max ()),
    m_minRtt (Time::Max ()),
    m_rttInitialized (false),
    m_alpha (0.125),
    m_k (0.5),
    m_gammaMin (0.5),
    m_gammaMax (1.5),
    m_rttThresholdUp (1.1),
    m_rttThresholdDown (0.9),
    m_lastGamma (1.0)
{
  NS_LOG_FUNCTION (this);
}

TcpCubicRttAware::TcpCubicRttAware (const TcpCubicRttAware& sock)
  : TcpCubicCustom (sock),
    m_rttSmooth (sock.m_rttSmooth),
    m_rttBaseline (sock.m_rttBaseline),
    m_minRtt (sock.m_minRtt),
    m_rttInitialized (sock.m_rttInitialized),
    m_alpha (sock.m_alpha),
    m_k (sock.m_k),
    m_gammaMin (sock.m_gammaMin),
    m_gammaMax (sock.m_gammaMax),
    m_rttThresholdUp (sock.m_rttThresholdUp),
    m_rttThresholdDown (sock.m_rttThresholdDown),
    m_lastGamma (sock.m_lastGamma)
{
  NS_LOG_FUNCTION (this);
}

TcpCubicRttAware::~TcpCubicRttAware ()
{
  NS_LOG_FUNCTION (this);
}

Ptr<TcpCongestionOps>
TcpCubicRttAware::Fork ()
{
  return CopyObject<TcpCubicRttAware> (this);
}

void
TcpCubicRttAware::PktsAcked (Ptr<TcpSocketState> tcb, uint32_t packetsAcked, const Time& rtt)
{
  NS_LOG_FUNCTION (this << tcb << packetsAcked << rtt);

  // Only process valid RTT samples
  if (rtt.IsZero () || rtt == Time::Max ())
    {
      return;
    }

  // Update minimum RTT (persistent baseline)
  if (rtt < m_minRtt)
    {
      m_minRtt = rtt;
    }

  // Initialize or update EWMA-smoothed RTT
  if (!m_rttInitialized)
    {
      m_rttSmooth = rtt;
      m_rttBaseline = rtt;
      m_rttInitialized = true;
      NS_LOG_DEBUG ("RTT initialized: smooth=" << m_rttSmooth.GetMilliSeconds ()
                    << "ms, baseline=" << m_rttBaseline.GetMilliSeconds () << "ms");
    }
  else
    {
      // EWMA: rtt_smooth = α * rtt_sample + (1-α) * rtt_smooth_prev
      m_rttSmooth = Time::FromDouble (m_alpha * rtt.GetSeconds ()
                                      + (1.0 - m_alpha) * m_rttSmooth.GetSeconds (),
                                      Time::S);
    }

  // Periodically update baseline to minimum RTT (adapts to route changes)
  // Use minRTT as baseline for more stable trend detection
  m_rttBaseline = m_minRtt;

  NS_LOG_DEBUG ("RTT update: sample=" << rtt.GetMilliSeconds ()
                << "ms, smooth=" << m_rttSmooth.GetMilliSeconds ()
                << "ms, baseline=" << m_rttBaseline.GetMilliSeconds ()
                << "ms, min=" << m_minRtt.GetMilliSeconds () << "ms");
}

double
TcpCubicRttAware::CalculateGamma () const
{
  // If RTT not yet initialized, use neutral gamma
  if (!m_rttInitialized || m_rttBaseline.IsZero () || m_rttBaseline == Time::Max ())
    {
      return 1.0;
    }

  // Calculate RTT ratio: current_smooth / baseline
  double rttRatio = m_rttSmooth.GetSeconds () / m_rttBaseline.GetSeconds ();

  // Gamma formula: γ = 1 / (1 + k · (rtt_ratio - 1))
  // When rtt_ratio > 1 (RTT increasing): γ < 1 (slow down growth)
  // When rtt_ratio < 1 (RTT decreasing): γ > 1 (speed up growth)
  double gamma = 1.0 / (1.0 + m_k * (rttRatio - 1.0));

  // Clamp to safe range
  gamma = std::max (m_gammaMin, std::min (m_gammaMax, gamma));

  NS_LOG_DEBUG ("Gamma calculation: rttRatio=" << rttRatio
                << ", gamma=" << gamma
                << " (rttSmooth=" << m_rttSmooth.GetMilliSeconds ()
                << "ms, baseline=" << m_rttBaseline.GetMilliSeconds () << "ms)");

  return gamma;
}

void
TcpCubicRttAware::UpdateRttBaseline ()
{
  // Reset baseline to current minimum RTT
  // Called on entering new CUBIC epoch (after congestion event)
  if (m_rttInitialized)
    {
      m_rttBaseline = m_minRtt;
      NS_LOG_DEBUG ("RTT baseline reset to minRTT: " << m_rttBaseline.GetMilliSeconds () << "ms");
    }
}

void
TcpCubicRttAware::IncreaseWindow (Ptr<TcpSocketState> tcb, uint32_t segmentsAcked)
{
  NS_LOG_FUNCTION (this << tcb << segmentsAcked);

  // In slow start, use default CUBIC behavior (no RTT adjustment)
  if (tcb->m_cWnd < tcb->m_ssThresh)
    {
      TcpCubicCustom::IncreaseWindow (tcb, segmentsAcked);
      return;
    }

  // ── Congestion avoidance with RTT-aware adjustment ────────────────

  // Save current cwnd
  uint32_t oldCwnd = tcb->m_cWnd;

  // Calculate base CUBIC window (calls parent's cubic calculation)
  TcpCubicCustom::IncreaseWindow (tcb, segmentsAcked);

  // Calculate the CUBIC increase
  uint32_t cubicIncrease = tcb->m_cWnd - oldCwnd;

  // Calculate gamma based on current RTT trend
  double gamma = CalculateGamma ();
  m_lastGamma = gamma;

  // Apply gamma adjustment to the increase
  // W_modified = W_old + gamma * (W_cubic - W_old)
  uint32_t adjustedIncrease = static_cast<uint32_t> (gamma * cubicIncrease);

  // Set the adjusted cwnd
  tcb->m_cWnd = oldCwnd + adjustedIncrease;

  NS_LOG_DEBUG ("RTT-aware window update: oldCwnd=" << oldCwnd
                << " cubicCwnd=" << (oldCwnd + cubicIncrease)
                << " gamma=" << gamma
                << " adjustedCwnd=" << tcb->m_cWnd);
}

void
TcpCubicRttAware::CongestionStateSet (Ptr<TcpSocketState> tcb,
                                      const TcpSocketState::TcpCongState_t newState)
{
  NS_LOG_FUNCTION (this << tcb << newState);

  // Call parent implementation (handles ssthresh update, epoch reset)
  TcpCubicCustom::CongestionStateSet (tcb, newState);

  // On entering recovery (loss detected), reset RTT baseline
  if (newState == TcpSocketState::CA_RECOVERY ||
      newState == TcpSocketState::CA_LOSS)
    {
      UpdateRttBaseline ();
    }
}

} // namespace ns3
