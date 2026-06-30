/** Scrolling AI disclaimer under app title — width matches title only. */

const DISCLAIMER =
  '1. AI 提供的内容仅供参考，请务必再三核实，亲自判断准确性；2. 务必亲自核实口径适用场景，防止误差';

export default function AiDisclaimerNotice() {
  return (
    <div className="ai-disclaimer-marquee" aria-label={DISCLAIMER}>
      <div className="ai-disclaimer-marquee__track">
        <span>{DISCLAIMER}</span>
        <span aria-hidden="true">{DISCLAIMER}</span>
      </div>
    </div>
  );
}
