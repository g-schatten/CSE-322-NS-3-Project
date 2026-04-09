#ifndef TCP_CUBIC_CUSTOM_H
#define TCP_CUBIC_CUSTOM_H

#include "tcp-congestion-ops.h"
#include "ns3/nstime.h"

namespace ns3 {

class TcpCubicCustom : public TcpCongestionOps
{
public:
  static TypeId GetTypeId (void);
  TcpCubicCustom ();
  TcpCubicCustom (const TcpCubicCustom& sock);
  virtual ~TcpCubicCustom ();

  virtual std::string GetName () const override;
  virtual Ptr<TcpCongestionOps> Fork () override;

  virtual void IncreaseWindow (Ptr<TcpSocketState> tcb,
                               uint32_t segmentsAcked) override;

  virtual uint32_t GetSsThresh (Ptr<const TcpSocketState> tcb,
                                uint32_t bytesInFlight) override;

  virtual void CongestionStateSet (Ptr<TcpSocketState> tcb,
                                   const TcpSocketState::TcpCongState_t newState) override;

private:
  uint32_t CubicUpdate (Ptr<TcpSocketState> tcb);
  void CubicReset (Ptr<const TcpSocketState> tcb);

  // CUBIC parameters
  double m_c;              // Scaling factor C
  double m_beta;           // Multiplicative decrease factor
  uint32_t m_smax;         // Maximum increment (segments per second)

  // State variables
  uint32_t m_wMax;         // Window size before last reduction (bytes)
  Time m_epochStart;       // Start time of current epoch
  Time m_lastUpdate;       // Last time window was updated
  uint32_t m_cntClamp;     // Counter for segments until next window increase
};

} // namespace ns3

#endif
