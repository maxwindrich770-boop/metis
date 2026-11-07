// Real installed Sonner, exercised inside the native WKWebView with test data.
import React from "react";
import { createRoot } from "react-dom/client";
import { Toaster, toast } from "sonner";

function measure() {
  const probe = document.getElementById("safe-area-probe")!;
  const safe = getComputedStyle(probe);
  const cards = Array.from(document.querySelectorAll<HTMLElement>(
    '[data-sonner-toaster][data-y-position="top"] [data-sonner-toast][data-mounted="true"]'
  )).filter(card => card.dataset.removed !== "true" && card.dataset.visible !== "false");
  const boxes = cards.map(card => card.getBoundingClientRect());
  const metrics = {
    count: boxes.length,
    safeTop: parseFloat(safe.paddingTop),
    safeLeft: parseFloat(safe.paddingLeft),
    safeRight: parseFloat(safe.paddingRight),
    minTop: boxes.length ? Math.min(...boxes.map(box => box.top)) : null,
    minLeft: boxes.length ? Math.min(...boxes.map(box => box.left)) : null,
    maxRight: boxes.length ? Math.max(...boxes.map(box => box.right)) : null,
    width: innerWidth,
  };
  document.getElementById("toast-metrics")!.textContent = "Notice geometry: " + JSON.stringify(metrics);
}

createRoot(document.getElementById("toast-root")!).render(
  <>
    <div className="metis-shell">
      <h1>Notification safe-area fixture</h1>
      <p>Real Sonner with synthetic messages; not a live run.</p>
      <button onClick={() => {
        toast.success("Run completed", { id: "fixture-completed", duration: Infinity });
        toast.info("Metis needs your input", { id: "fixture-question", duration: Infinity });
        toast.error("Test connection interrupted", { id: "fixture-error", duration: Infinity });
        setTimeout(measure, 600);
      }}>Show notification samples</button>
      <button onClick={() => setTimeout(measure, 400)}>Measure notification position</button>
      <button onClick={() => toast.dismiss()}>Dismiss notification samples</button>
    </div>
    <Toaster position="top-center" duration={Infinity} expand />
  </>
);
