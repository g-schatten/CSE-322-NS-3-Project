#include "tcp-cubic-custom.h"
#include "ns3/log.h"
#include "ns3/simulator.h"
#include "ns3/double.h"
#include "ns3/uinteger.h"
#include <cmath>

namespace ns3 {

NS_LOG_COMPONENT_DEFINE ("TcpCubicCustom");
NS_OBJECT_ENSURE_REGISTERED (TcpCubicCustom);

TypeId
TcpCubicCustom::GetTypeId (void)
{
  static TypeId tid = TypeId ("ns3::TcpCubicCustom")
    .SetParent<TcpCongestionOps> ()
    .SetGroupName ("Internet")
    .AddConstructor<TcpCubicCustom> ()
    .AddAttribute ("C", "CUBIC scaling factor",
                   DoubleValue (0.4),
                   MakeDoubleAccessor (&TcpCubicCustom::m_c),
                   MakeDoubleChecker<double> (0.0))
    .AddAttribute ("Beta", "CUBIC multiplicative decrease factor",
                   DoubleValue (0.8),
                   MakeDoubleAccessor (&TcpCubicCustom::m_beta),
                   MakeDoubleChecker<double> (0.0, 1.0))
    .AddAttribute ("Smax", "Maximum window increment per second (segments)",
                   UintegerValue (160),
                   MakeUintegerAccessor (&TcpCubicCustom::m_smax),
                   MakeUintegerChecker<uint32_t> ());
  return tid;
}

TcpCubicCustom::TcpCubicCustom ()
  : TcpCongestionOps (),
    m_c (0.4),
    m_beta (0.8),
    m_smax (160),
    m_wMax (0),
    m_epochStart (Time::Min ()),
    m_lastUpdate (Time::Min ()),
    m_cntClamp (0)
{
  NS_LOG_FUNCTION (this);
}

TcpCubicCustom::TcpCubicCustom (const TcpCubicCustom& sock)
  : TcpCongestionOps (sock),
    m_c (sock.m_c),
    m_beta (sock.m_beta),
    m_smax (sock.m_smax),
    m_wMax (sock.m_wMax),
    m_epochStart (sock.m_epochStart),
    m_lastUpdate (sock.m_lastUpdate),
    m_cntClamp (sock.m_cntClamp)
{
  NS_LOG_FUNCTION (this);
}

TcpCubicCustom::~TcpCubicCustom ()
{
  NS_LOG_FUNCTION (this);
}

std::string
TcpCubicCustom::GetName () const
{
  return "TcpCubicCustom";
}

Ptr<TcpCongestionOps>
TcpCubicCustom::Fork ()
{
  return CopyObject<TcpCubicCustom> (this);
}

void
TcpCubicCustom::CubicReset (Ptr<const TcpSocketState> tcb)
{
  NS_LOG_FUNCTION (this);

  // Reset epoch timing only.
  // m_wMax is intentionally preserved: it is set by GetSsThresh at every
  // loss event and must survive state transitions so that IncreaseWindow
  // can grow the window back toward the pre-loss peak.
  m_epochStart = Time::Min ();
  m_lastUpdate = Time::Min ();
  m_cntClamp = 0;
}

uint32_t
TcpCubicCustom::CubicUpdate (Ptr<TcpSocketState> tcb)
{
  NS_LOG_FUNCTION (this << tcb);

  Time currentTime = Simulator::Now ();

  // If this is the first update after a loss event
  if (m_epochStart == Time::Min ())
    {
      m_epochStart = currentTime;
      m_lastUpdate = currentTime;

      if (m_wMax == 0)
        {
          // If we don't have a previous wMax, start from current window
          m_wMax = tcb->m_cWnd;
        }

      NS_LOG_DEBUG ("New epoch started at " << currentTime.GetSeconds ()
                    << "s, wMax=" << m_wMax);
    }

  // Calculate elapsed time since last loss event (in seconds)
  double t = (currentTime - m_epochStart).GetSeconds ();

  // Calculate K = cube_root(Wmax * beta / C)
  // K is the time period that CUBIC takes to increase window to Wmax
  double k = std::cbrt (m_wMax * (1.0 - m_beta) / m_c / tcb->m_segmentSize);

  // Calculate target window: W_cubic = C * (t - K)^3 + Wmax
  double target = m_c * std::pow (t - k, 3) + m_wMax;

  NS_LOG_DEBUG ("t=" << t << "s, K=" << k << "s, target=" << target);

  // Calculate TCP-friendly window (Equation 4 from paper)
  // W_tcp = Wmax * beta + 3(1-beta)/(1+beta) * t/RTT
  // Guard against zero RTT before the first sample is available.
  double rtt = tcb->m_lastRtt.Get ().GetSeconds ();
  if (rtt > 0.0)
    {
      double tcpFriendly = m_wMax * m_beta +
                           3.0 * (1.0 - m_beta) / (1.0 + m_beta) *
                           (t / rtt) * tcb->m_segmentSize;

      NS_LOG_DEBUG ("TCP-friendly window=" << tcpFriendly);

      // Use the larger of cubic target and TCP-friendly window
      if (tcpFriendly > target)
        {
          target = tcpFriendly;
          NS_LOG_DEBUG ("Using TCP-friendly mode");
        }
    }

  // Clamp window increment to Smax segments per second
  if (m_lastUpdate != Time::Min ())
    {
      double timeDelta = (currentTime - m_lastUpdate).GetSeconds ();
      double maxIncrement = m_smax * tcb->m_segmentSize * timeDelta;
      double currentIncrement = target - tcb->m_cWnd.Get ();

      if (currentIncrement > maxIncrement)
        {
          target = tcb->m_cWnd.Get () + maxIncrement;
          NS_LOG_DEBUG ("Clamping increment to " << maxIncrement
                        << " bytes (Smax=" << m_smax << " segs/s)");
        }
    }

  m_lastUpdate = currentTime;

  // Ensure target is at least current window size
  if (target < tcb->m_cWnd.Get ())
    {
      target = tcb->m_cWnd.Get ();
    }

  NS_LOG_DEBUG ("CUBIC target window=" << target << " current=" << tcb->m_cWnd.Get ());

  return static_cast<uint32_t> (target);
}

void
TcpCubicCustom::IncreaseWindow (Ptr<TcpSocketState> tcb, uint32_t segmentsAcked)
{
  NS_LOG_FUNCTION (this << tcb << segmentsAcked);

  if (tcb->m_cWnd < tcb->m_ssThresh)
    {
      // Slow start: exponential growth
      NS_LOG_DEBUG ("In slow start, increasing cwnd");
      tcb->m_cWnd += segmentsAcked * tcb->m_segmentSize;
    }
  else
    {
      // Congestion avoidance: use CUBIC
      NS_LOG_DEBUG ("In congestion avoidance, using CUBIC");

      if (segmentsAcked > 0)
        {
          uint32_t targetCwnd = CubicUpdate (tcb);

          // Calculate how much to increase per ACK
          uint32_t gap = targetCwnd - tcb->m_cWnd.Get ();
          if (gap < tcb->m_segmentSize)
            {
              // Already at or very near target — add one segment
              tcb->m_cWnd += tcb->m_segmentSize;
            }
          else
            {
              double cnt = static_cast<double> (tcb->m_cWnd.Get ()) /
                           static_cast<double> (gap);

              if (cnt < 1.0)
                {
                  tcb->m_cWnd += tcb->m_segmentSize;
                  NS_LOG_DEBUG ("Fast increase: cwnd=" << tcb->m_cWnd);
                }
              else
                {
                  m_cntClamp += segmentsAcked;
                  uint32_t increment = static_cast<uint32_t> (m_cntClamp / cnt);

                  if (increment > 0)
                    {
                      tcb->m_cWnd += increment * tcb->m_segmentSize;
                      m_cntClamp -= static_cast<uint32_t> (increment * cnt);
                      NS_LOG_DEBUG ("Slow increase: cwnd=" << tcb->m_cWnd
                                    << " cnt=" << cnt);
                    }
                }
            }
        }
    }
}

uint32_t
TcpCubicCustom::GetSsThresh (Ptr<const TcpSocketState> tcb, uint32_t bytesInFlight)
{
  NS_LOG_FUNCTION (this << tcb << bytesInFlight);

  // Store wMax before reduction
  m_wMax = tcb->m_cWnd.Get ();

  // Reset epoch start to trigger new epoch on next window increase
  m_epochStart = Time::Min ();
  m_lastUpdate = Time::Min ();
  m_cntClamp = 0;

  // CUBIC multiplicative decrease: cwnd = beta * cwnd
  uint32_t ssthresh = static_cast<uint32_t> (tcb->m_cWnd.Get () * m_beta);

  NS_LOG_DEBUG ("Loss detected: wMax=" << m_wMax << " new ssthresh=" << ssthresh);

  return std::max (2 * tcb->m_segmentSize, ssthresh);
}

void
TcpCubicCustom::CongestionStateSet (Ptr<TcpSocketState> tcb,
                                    const TcpSocketState::TcpCongState_t newState)
{
  NS_LOG_FUNCTION (this << tcb << newState);

  // GetSsThresh already resets epoch state at every loss event, so no action
  // is needed here.  Resetting again on CA_OPEN would corrupt the epoch
  // start time in the middle of a recovery and mis-shape the cubic curve.
}

} // namespace ns3
