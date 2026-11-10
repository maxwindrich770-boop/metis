// Real quota and context components with explicitly synthetic usage data.
import React from "react";
import { createRoot } from "react-dom/client";
import { PlanUsageGauge, ContextUsageText } from "../../../components/quota-gauges";

const provider = {
  key: "fixture", name: "Synthetic provider", status: "live" as const,
  windows: [
    { label: "Sample window", usedPercent: 25, resetsAt: null },
    { label: "Second sample", usedPercent: 40, resetsAt: null },
  ],
};
function measure() {
  const usage = document.querySelector<HTMLElement>('[data-metis-app-usage]');
  const context = document.querySelector<HTMLElement>('[data-slot="tooltip-content"]:not([data-metis-app-usage])');
  const surface = usage || context;
  const box = surface?.getBoundingClientRect();
  const heading = surface?.querySelector('p');
  const title = heading?.getBoundingClientRect();
  const value = {
    width: innerWidth, height: innerHeight, usage: Boolean(usage),
    left: box?.left, right: box?.right, cardWidth: box?.width,
    titleCenter: title ? (title.left + title.right) / 2 : null,
    align: heading ? getComputedStyle(heading).textAlign : null,
    fontSize: heading ? getComputedStyle(heading).fontSize : null,
  };
  document.getElementById("usage-metrics")!.textContent = "Usage geometry: " + JSON.stringify(value);
}
createRoot(document.getElementById("usage-root")!).render(
  <>
    <div className="flex justify-end gap-4 p-4" aria-label="Synthetic composer controls">
      <PlanUsageGauge provider={provider} />
      <ContextUsageText used={100} total={1000} />
    </div>
    <main className="p-4">
      <h1>Synthetic usage layout fixture</h1>
      <p>The actual quota tooltip with test values; no live quota claim.</p>
      <button onClick={measure}>Measure usage layout</button>
    </main>
    <aside hidden><button aria-label="Open account menu">Fixture account</button></aside>
  </>
);
setInterval(measure, 150);
