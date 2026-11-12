// Real project note buttons with a synthetic route host reproducing AppShell's
// project-route effect. No production notes, projects or accounts are changed.
import { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { ProjectHome } from "../../../components/project-home";
import type { ProjectHomeData } from "../../../lib/project-home-client";

const originalFetch = window.fetch.bind(window);
window.fetch = async (input, init) => {
  const url = new URL(input instanceof Request ? input.url : String(input), location.href);
  const id = url.pathname.split("/").at(-1);
  if (url.origin === location.origin && (id === "fixture-notes" || id === "fixture-empty") &&
      url.pathname === `/api/projects/${id}` && (!init?.method || init.method === "GET")) {
    const data: ProjectHomeData = {
      project: { id, name: "Synthetic project", membershipRole: "member", mode: "chat",
        icon: "folder", color: "#71816c", instructions: "", memoryMode: "default",
        disabledSkillIds: [], memories: [] },
      files: [], chats: [], skills: [],
      notes: id === "fixture-empty" ? [] : [
        { id: "first", title: "First project note" },
        { id: "second", title: "Second project note" },
      ],
    };
    return Response.json(data);
  }
  return originalFetch(input, init);
};
const initial = new URL(location.href);
initial.searchParams.set("c", "project:fixture-notes");
history.replaceState(history.state, "", initial);

function Fixture() {
  const [route, setRoute] = useState(() => new URL(location.href).searchParams.get("c"));
  const [notesOpen, setNotesOpen] = useState(false);
  const [noteId, setNoteId] = useState<string | null>(null);
  const [empty, setEmpty] = useState(false);
  useEffect(() => {
    const changed = () => setRoute(new URL(location.href).searchParams.get("c"));
    window.addEventListener("popstate", changed);
    return () => window.removeEventListener("popstate", changed);
  }, []);
  // Older AppShell versions rerun their route effect when notesOpen changes.
  useEffect(() => {
    if (route?.startsWith("project:")) setNotesOpen(false);
    else if (route === "notes") setNotesOpen(true);
  }, [route, notesOpen]);
  return <main className="metis-shell">
    <p>Synthetic route host with the real ProjectHome component.</p>
    <output>Route: {route}</output>
    {notesOpen ? <>
      <h1>{noteId ? `Opened note: ${noteId}` : "Opened notebook"}</h1>
      <button onClick={() => history.back()}>Back to project</button>
    </> : <>
      <button onClick={() => setEmpty(true)}>Open empty project</button>
      <ProjectHome projectId={empty ? "fixture-empty" : "fixture-notes"}
        onOpenChat={() => {}} onNewChat={() => {}} onAttachFile={() => {}} onDeleted={() => {}}
        onOpenNotes={id => { setNotesOpen(true); setNoteId(id ?? null); }} />
    </>}
  </main>;
}
createRoot(document.getElementById("project-notes-root")!).render(<Fixture />);
