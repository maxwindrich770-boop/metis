import { createRoot } from "react-dom/client";
import { useState } from "react";
import { MaintenanceScreen } from "../../../components/maintenance-screen";
import { activateInstallerMaintenanceScreen } from "../../../lib/update-job-client";

function UpdateFixture() {
  const [updating, setUpdating] = useState(false);
  const restored = new URL(location.href).searchParams.get("fixture") === "update-restart";
  if (restored) {
    localStorage.removeItem("metis-update-job");
    return <main><h1>Update verified — workspace restored</h1><p>The authenticated web workspace is available again.</p></main>;
  }
  if (updating) return <MaintenanceScreen reason="Synthetic installer restart test." logs={["Update job created.", "Installing the selected version…", "Restarting Metis…"]} />;
  return <main><h1>Server updates fixture</h1><button onClick={() => {
    localStorage.setItem("metis-update-job", "synthetic-ios-update");
    activateInstallerMaintenanceScreen("Synthetic installer restart test.");
    setUpdating(true);
    setTimeout(() => location.assign("/?fixture=update-restart"), 1200);
  }}>Update now</button></main>;
}

createRoot(document.getElementById("update-root")!).render(<UpdateFixture />);
