# Metis für iOS und Apple Watch — vollständiger Entwicklungsplan

> **Status:** Implementierung vorhanden; aktueller Phasenstand und Testnachweise unter `docs/APPLE-CLIENTS-IMPLEMENTATION.md`. Die offenen Kästchen unten sind die ursprünglichen Abnahmekriterien und keine aktuelle Fortschrittsanzeige.
> **Stand:** 06.11.2026
> **Projekt:** [f1shyondrugs/metis](https://github.com/f1shyondrugs/metis)  
> **Audit-Basis:** `master` bei `a5a70d4bbcb56c9a8cf582d37e3a7467840d35ce` (vor Implementierungsbeginn gegen HEAD prüfen).  
> **Ziel:** Eine echte, native, öffentlich über den Apple App Store verteilbare iPhone-App mit Push-Aktionen, ergänzt durch eine watchOS-App. Die vorhandene Metis-Web-App und alle bestehenden Installationen bleiben funktionsfähig.

---

## 0. Arbeitsauftrag für Codex

Du bist leitender Apple-/Full-Stack-Engineer für Metis. Setze diesen Plan **inkrementell und testgetrieben** um. Die existierende TypeScript-/Next.js-Anwendung ist der maßgebliche Server und die einzige Quelle für Benutzer, Chats, Agentenläufe und Entscheidungen. Baue **keine zweite Backend- oder Agenten-Engine**.

**Verbindliches Vorgehen:**

1. Lies zuerst `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/PRODUCTION-AUDIT.md`, die vorhandenen API-Handler, Auth-/Session-Logik, Datenbankmigrationen und Tests. Vergleiche dieses Dokument mit dem aktuellen Quellstand. Dokumentiere Abweichungen, statt Annahmen als Fakten zu behandeln.
2. Erfasse den Git-Status und erstelle einen eigenen Feature-Branch (`feat/apple-clients`). Keine bestehenden Nutzerdaten löschen, keine fremden Änderungen zurücksetzen, keine Tests umgehen.
3. Lege `docs/APPLE-CLIENTS-IMPLEMENTATION.md` mit Entscheidungen, API-Verträgen, Phasenstatus, Risiken und Testnachweisen an. Aktualisiere es mit jeder Phase.
4. Beginne mit einem **nutzbaren iOS-Chat-MVP**, dann Push und Approvals, dann watchOS, dann systemnahe Integrationen und Release. Jeder Meilenstein muss kompilieren und End-to-End testbar sein.
5. Fordere manuelle Eingaben nur dort an, wo Apple-Account, APNs-Key, Bundle-ID, Signierung, Gerätefreigaben oder App-Store-Connect-Zugriff unvermeidlich sind. Keine Zugangsdaten ins Repo oder in Chat-/Build-Logs.
6. Wenn eine Apple-Funktion wegen API-/SDK-/Geräte- oder App-Review-Regeln nicht nachweislich funktioniert, implementiere einen sauberen Fallback und dokumentiere ihn. Behaupte keinen Erfolg ohne echte Tests.
7. Erzeuge am Ende pro Phase eine kurze Übergabe: geänderte Dateien, neue API-Routen, Migrationen, ausgeführte Tests, offene Punkte, nächster Schritt. **Keine unaufgeforderten Deployments und keine App-Store-Veröffentlichung.**

### Unveränderliche Projektregeln

- Ein Metis-Account und seine bestehenden Daten müssen auf Web, iPhone und Watch konsistent bleiben.
- Der Server kontrolliert Berechtigungen. Eine mobile UI darf weder ACLs noch Genehmigungen umgehen.
- Keine WebView-Shell als Hauptanwendung; native SwiftUI-Screens sind das Ziel.
- Keine unnötigen neuen Cloud-Dienste; APNs ist für native Push-Benachrichtigungen nötig.
- Selbst gehostete Metis-Instanzen werden weiterhin unterstützt; die App benötigt keine zentralen Metis-Nutzerkonten.
- Keine direkten Shell-/Root-Rechte auf iOS oder watchOS; Gerätedaten nur über freigegebene Apple-APIs und explizite Nutzeraktionen.
- Geheimnisse nicht in Quellcode, Git, Push-Payloads, URLs, Telemetrie oder Watch-Synchronisierungsnachrichten hinterlegen.

---

## 1. Produktvision und Umfang

### 1.1 Nutzererlebnis

Der Nutzer öffnet die Metis-App auf dem iPhone, verbindet sie einmal mit seiner Metis-Serveradresse und meldet sich an. Danach stehen dieselben Chats und laufenden Agenten wie im Browser zur Verfügung. Antworten erscheinen als Stream; neue Nachrichten, Dateien, Spracheingaben und Modellwahl funktionieren nativ.

Während Metis im Hintergrund arbeitet, erhält der Nutzer **konfigurierbare Push-Benachrichtigungen** bei fertiggestellten Runs, Fragen, Fehlern und anstehenden Freigaben. Unkritische Entscheidungen können — nach einer explizit definierten Sicherheitsrichtlinie — über Benachrichtigungsaktionen erfolgen. Bei riskanten Aktionen öffnet die Nachricht zwingend die App und fordert eine zusätzliche Bestätigung an.

Eine ergänzende Apple-Watch-App zeigt die wichtigsten offenen Vorgänge, erlaubt einfache Entscheidungen und das Erstellen kurzer Sprach-/Textprompts. Erweiterte Inhalte bleiben auf dem iPhone.

### 1.2 Priorität und Releaseumfang

| Stufe | Funktionen | Statusziel |
|---|---|---|
| **P0 – zwingend für erste nutzbare Version** | Server-Verbindung, Anmeldung/Abmeldung, Chatliste, Chatinhalte, neue Chats, Nachrichten senden, Run-Streaming, Lauf abbrechen, Fehler-/Offlinezustände | iOS-MVP |
| **P1 – Kernmerkmal** | APNs-Push, Inbox, zuverlässiges Device-Register, sichere Approvals und Antworten auf Agentenfragen, Deeplinks | Mobile Beta |
| **P2 – produktiv nutzbar** | Datei-/Bild-Upload, Voice-Eingabe, Modellauswahl, Projekte/Agenten-Übersicht, Suche, Einstellungen, Push-Filter | iOS-Release-Kandidat |
| **P3 – Watch** | Offene Entscheidungen, Run-Status, Kurzprompt per Diktat/Text, Ergebnis-Feedback, WatchConnectivity | watchOS Beta |
| **P4 – Geräteintegrationen** | Fotos, Kamera, Dateiauswahl, Teilen-Menü, Kurzbefehle/App Intents, optional Kalender/Kontakte/Standort mit Einzelberechtigungen | optionale Updates |
| **P5 – fortgeschritten** | Widgets/Komplikationen, erweiterte Sprache, geräteübergreifende Handoff-Aktionen, Offline-Entwürfe | später |

**Nicht Ziel des ersten Releases:** volle Desktop-Terminalansicht, komplexe Browser-Remote-Steuerung, sämtliche Workspace-Canvas-Funktionen, permanentes Mithören, beliebiger App-Zugriff, allgemeines iPhone-Computer-Use oder eigenständige Agentenausführung auf der Watch.

### 1.3 Definition „wie die Web-App“

- Der Funktionsumfang wird schrittweise **auf dieselben Server-Ressourcen** abgebildet; ein pixelgenauer Web-Nachbau ist nicht sinnvoll.
- Native Navigation und iOS-Konventionen haben Vorrang vor dem Desktop-Layout.
- Jedes Feature muss entweder nativ vorhanden sein, klar als „auf dem Web öffnen“ gekennzeichnet sein oder bewusst als späterer Ausbau gelistet werden.
- Bestehende Chats, Modelle, Attachments, Projekte, Rollen, Run-Status und Agentenfragen werden nicht dupliziert.

---

## 2. Verifizierte Metis-Ausgangslage (Repo-Audit)

**Bei der Sichtung des öffentlichen Repos am 03.11.2026 gefunden:**

- Server/Frontend: **Next.js + TypeScript**, Node.js >=22, `pnpm`, eigener Start via `server.mjs`.
- `app/` enthält UI und API-Handler; `lib/` Agent-/Auth-/Datenbanklogik; `components/` Web-UI; `packages/mcp-gateway/` MCP-System.
- Chatverlauf, laufende Agenten, Voice-Transkription, Agentenfragen, Approvals und Benachrichtigungen existieren bereits.
- Auth: `POST /api/auth` legt ein **HttpOnly-/SameSite-Cookie** an; `DELETE /api/auth` meldet ab. Bestehende Sessions müssen serverseitig gültig bleiben.
- `GET/POST /api/chats`: Chatliste und Chat anlegen.
- `GET /api/chats/[id]`: paginierte Chat-Nachrichten (`messageLimit`, `messageOffset`, `messageBefore`) mit `ETag`; `PATCH` für Chatänderungen.
- `POST /api/chat`: existierende Submit-Pipeline mit Worker-Offloading. Für den nativen Client ist vorzugsweise der bestehende Run-Pfad zu verwenden, wenn er denselben fachlichen Ablauf korrekt abbildet.
- `POST /api/runs`: Nachricht/Attachments an Chat senden und Job anlegen; der Request akzeptiert u. a. `chatId`, `message`, `messageId`, `modelId`, `modelParams`.
- `GET /api/runs?chatId=...&events=1&stream=1`: **SSE-Run-Events** mit Cursor/Resume; `GET /api/runs?...` listet Jobs/Events.
- `GET /api/chats/events`: **SSE-Chat-Synchronisierung** mit Cursor und Heartbeat.
- `GET /api/chats/status?ids=...`: kompakte Run-Statusabfrage.
- `POST /api/chat/approval`: Genehmigung per `approvalId`, `decision` (`allow`, `allow-session`, `deny`), optional `version`.
- `POST /api/chat/answer`: Fragen beantworten (`questionId`, `answers`/`values`, optional `version`).
- `POST /api/chat/cancel` und `POST /api/chat/resume`: abbrechen bzw. unterbrochene Agentenläufe fortführen. Signaturen vor Implementierung prüfen.
- `GET/PATCH/POST /api/notifications`: bestehender Feed, Präferenzen und Benachrichtigungsobjekte. Das bestehende native Delivery-Backend zielt teilweise auf **Remote-Desktop-Clients über WebSockets**, **nicht bereits automatisch auf APNs**.
- `GET/POST /api/notifications/inbox`: separat vorhandener projektbezogener Inbox-Mechanismus. Die beiden Notification-Domänen nicht ohne Analyse vermischen.
- `/api/voice/transcribe`: Server-Transkriptionsfunktion, deren genaue Multipart-/Job-Schnittstelle vor Verwendung nachzuvollziehen ist.
- Vorhandene Modelle und Projekte sind durch `app/api/models`, `app/api/projects`, `app/api/agent-settings` und weitere API-Verzeichnisse erkennbar, **deren konkrete Antwortschemas noch zu prüfen sind**.

**Primäre Code-Einstiege:**

- [README](https://github.com/f1shyondrugs/metis/blob/master/README.md)
- [AGENTS.md](https://github.com/f1shyondrugs/metis/blob/master/AGENTS.md)
- [SECURITY.md](https://github.com/f1shyondrugs/metis/blob/master/SECURITY.md)
- [Chat-Routen](https://github.com/f1shyondrugs/metis/tree/master/app/api/chats)
- [Runs-Route](https://github.com/f1shyondrugs/metis/blob/master/app/api/runs/route.ts)
- [Chat-Approval-Route](https://github.com/f1shyondrugs/metis/blob/master/app/api/chat/approval/route.ts)
- [Notification-Store](https://github.com/f1shyondrugs/metis/blob/master/lib/notification-store.ts)
- [Remote-Notification-Bindings](https://github.com/f1shyondrugs/metis/blob/master/lib/notification-remote.ts)

### 2.1 Was vor dem Implementieren noch zu verifizieren ist

- Exaktes JSON-Format von Chatliste, Chatpage, Job-Events und Modellen.
- Ob `POST /api/runs` ausreichend für alle Nachrichten-/Rollen-/Agent-Varianten ist oder `POST /api/chat` für einzelne Fälle nötig bleibt.
- Auth-Cookie-Name, Ablaufzeiten, Session-Rotation, CSRF/Origin-Schutz für Nicht-Browser-Clients.
- Attachment-Protokoll, Chunk-/Dateilimits und erlaubte MIME-Typen.
- Konkrete Run-Event-Typen, Message-Pagination und Wiederaufnahme nach Netzwerkverlust.
- Laufzeitmodell der bestehenden Notification-Beobachtung (besonders pro User, pro Run, Abschluss/Fehler/Approval).
- API-Versionierung und Abwärtskompatibilität bei alten mobilen Clients.
- Welche Daten iOS/Watch ohne weitere Serveränderungen bereits nutzen dürfen.

Ergebnis: `docs/APPLE-API-INVENTORY.md` mit Endpunkten, Request-/Response-Beispielen (ohne Secrets), Auth-Erfordernissen, Statuscodes, Rate Limits und Verantwortlichkeiten.

---

## 3. Architekturentscheidung

### 3.1 Empfohlener Stack

| Schicht | Technologie | Begründung |
|---|---|---|
| iPhone | **Swift + SwiftUI** | Native Bedienung, Bedienungshilfen, App Store, Benachrichtigungen, Geräteberechtigungen |
| Watch | **SwiftUI für watchOS** | Kleine native Interaktionen und Apple-Watch-Integration |
| Netzwerk | `URLSession` + `async/await` | Standard-HTTPS, Cookie-Sessions, Uploads, Streams |
| Live-Events | SSE-Parser über `URLSession.bytes` (oder bewährte kleine Library nach Review) | Metis hat SSE bereits; kein unnötiges zweites Realtime-Protokoll |
| State | `Observable`/`ObservableObject` passend zum Minimal-Deployment-Target | Übersichtliche Trennung von Daten und UI |
| Auth | Metis-Session über `URLSession`-Cookie-Handling; Keychain nur für notwendige lokale Secrets | Kein paralleler Account-Provider |
| Push | **Apple Push Notification service (APNs)** mit tokenbasiertem Backend | Standard für native Remote-Push |
| Watch-Kopplung | **WatchConnectivity** | Kurze Aktionen/Status, optional mit serverseitiger Watch-Session |
| Optional | App Intents / Shortcuts / Share Extension | Kontrollierte Integration in iOS |
| Deployment | Xcode, App Store Connect, TestFlight | Offizieller Veröffentlichungsweg |

**Warum nicht PWA/Capacitor/React-Native-Wrapper als Default?** Die Web-App ist bereits vorhanden, aber die wichtigsten neuen Alleinstellungsmerkmale sind native Push-Aktionen, Watch-Integration, Shortcuts und kontrollierter Gerätezugriff. SwiftUI verringert die Brüche zwischen diesen Apple-Funktionen. Eine WebView darf später für besonders komplexe, sekundäre Ansichten verwendet werden, nicht als Ersatz der nativen Haupt-App.

### 3.2 Datenfluss

```text
                         ┌────────────────────────────────────┐
                         │ Bestehende Metis-Instanz           │
                         │ Next.js API + Agent Worker + DB   │
                         │ Einzige Source of Truth           │
                         └─────────┬──────────┬──────────────┘
                                   │ HTTPS/SSE │ Ereignisse
                    ┌──────────────┘          ▼
                    │                  ┌───────────────────┐
                    │                  │ Mobile Push       │
                    │                  │ Adapter + Outbox  │
                    │                  └────────┬──────────┘
                    ▼                           │ APNs HTTP/2
        ┌──────────────────────┐                ▼
        │ Metis iOS (SwiftUI)  │       ┌───────────────────┐
        │ Chats + Device APIs  │◄──────│ Apple APNs        │
        │ Sessions + Approval  │       └───────────────────┘
        └─────────┬────────────┘                │
                  │ WatchConnectivity          │ iPhone/Watch
                  ▼                            ▼
        ┌──────────────────────┐       Benachrichtigungen
        │ Metis watchOS        │       und systemeigene Aktionen
        │ Status/Prompt/Approve│
        └──────────────────────┘
```

**Wichtig:** APNs ist nur ein Zustelltransport, **kein** Ausführungs- oder Entscheidungsbackend. Jede Aktion wird am Metis-Server mit Auth, Owner-Zuordnung, Rollen, ETag/Version, Ablaufzeit und Idempotenz erneut geprüft.

### 3.3 Vorgeschlagene Repo-Struktur (an bestehende Konventionen anpassen)

```text
metis/
├── app/api/mobile/
│   ├── capabilities/route.ts
│   ├── devices/route.ts
│   ├── devices/[id]/route.ts
│   ├── notifications/route.ts         # falls bestehende API kein sauberes Contract bietet
│   └── actions/[id]/route.ts          # bevorzugt Adapter auf bestehende Approval-/Question-Logik
├── lib/mobile/
│   ├── device-store.ts
│   ├── apns-provider.ts
│   ├── push-outbox.ts
│   ├── event-adapter.ts
│   ├── action-policy.ts
│   └── schemas.ts
├── tests/mobile/
│   ├── auth.test.ts
│   ├── devices.test.ts
│   ├── apns.test.ts
│   ├── actions.test.ts
│   └── isolation.test.ts
├── clients/apple/
│   ├── MetisApple.xcodeproj
│   ├── Shared/
│   ├── MetisiOS/
│   ├── MetisWatch/
│   ├── MetisShareExtension/             # optional ab P4
│   ├── MetisAppIntents/                 # falls als eigenständiges Target nötig
│   ├── Tests/
│   └── README.md
└── docs/
    ├── APPLE-CLIENTS-IMPLEMENTATION.md
    ├── APPLE-API-INVENTORY.md
    ├── APPLE-SECURITY-MODEL.md
    └── APPSTORE-RELEASE-CHECKLIST.md
```

**Prinzip:** Ein Repo ist für den Start am einfachsten. iOS- und watchOS-Code in separaten Targets mit gemeinsamem Daten-/Netzwerkmodul. Das Xcode-Projekt wird reproduzierbar eingecheckt; keine auf dem Entwickler-Mac versteckten Projektdateien.

---

## 4. iPhone-App: UX und technische Features

### 4.1 Informationsarchitektur

**Tab-Bar:** `Chats` · `Aktivität` · `Projekte` · `Einstellungen`. Offene Genehmigungen zusätzlich als gut sichtbare Inbox-/Badge-Anzeige. Auf kleinen Displays keine Desktop-Sidebars erzwingen.

**Chats:** Suchfeld, Neu-Chat-Button, angeheftete/archivierte Chats, zuletzt aktiv, sichtbarer Laufstatus, Pull-to-Refresh. Chatliste inkrementell und ohne Vollrefresh nach SSE aktualisieren.

**Chatdetail:** Benutzer-/Agentennachrichten, korrekt umbrochener Markdown-Text, sichere Links, Codeblöcke mit Kopieren, Bilder/Dateien, Tool- und Reasoning-/Progress-Blöcke als aufklappbare Abschnitte, Antwort-Streaming, Abbrechen, Weiterführen, Warten auf Rückfrage, Eingabefeld mit Attachments/Mikrofon. Rendering muss auf sehr lange Verläufe vorbereitet sein (Lazy-Listen + Pagination).

**Aktivität:** laufende Jobs, ausstehende Genehmigungen/Fragen, abgeschlossene Aufgaben, Fehlermeldungen, Benachrichtigungsfeed. Nach fehlender Push-Zustellung immer aus Serverstatus rekonstruierbar.

**Projekte:** zunächst nur vorhandene Projekte, Chatzuordnung und einfache Agentenstatusansichten; komplexe Projekt-Editoren später.

**Einstellungen:** Server-Adresse, Kontoinfo, Anmeldung, Geräteliste, Benachrichtigungsregeln, Datenschutz/Permissions, Watch-Status, App-Version, Diagnostik-Export ohne Secrets.

### 4.2 Verbindung und Anmeldung

1. Beim ersten Start: „Mit Metis-Server verbinden“ mit HTTPS-URL; optional QR-Code vom Web-Account als Bequemlichkeitsfunktion **ohne** langfristiges API-Secret im QR-Code.
2. Normalisierung auf **Origin** (`https://...`); keine beliebigen Pfade, Redirects oder HTTP-Downgrades akzeptieren.
3. Host/Erreichbarkeit und TLS-Zertifikat regulär validieren; keine globale `allowsArbitraryLoads`-Ausnahme und kein „accept all certificates“.
4. `POST /api/auth`: bestehendes User-/Passwortformular. `URLSession` muss HttpOnly-Cookie korrekt speichern/senden. Keine Speicherung des Passworts, sofern der Nutzer das nicht ausdrücklich wünscht.
5. Erfolgreiche Session über sichere, authentifizierte Profil-/Me-Anfrage prüfen; Sessionablauf und 401 behandeln, Login-UI wieder einblenden.
6. Serverwechsel muss vorhandene SSE-Tasks, Cookies, Push-Gerätezuteilung, Offline-Caches und Watch-Status **sauber isolieren**.
7. Logout: Server-Session widerrufen, Device-Registrierung entfernen, sensitive lokale Daten löschen, Watch-Verknüpfung invalidieren. Bei Offline-Logout lokale Credentials sofort entfernen und serverseitige Abmeldung beim nächsten möglichen Kontakt nachziehen (mit klarer Security-Dokumentation).
8. Keine langfristigen Bearer-Tokens erfinden, solange der bestehende Cookie-Auth-Ansatz sicher funktioniert. Falls dedizierte Mobile-/Watch-Sessions nötig sind, separat modellieren und auditieren.

**Multi-Server:** fürs erste Release nur ein aktiver Server; Architektur so anlegen, dass später mehrere Instanzen als Profile möglich sind. Alle DB-Caches müssen pro `(normalizedServerOrigin, accountId)` getrennt sein.

### 4.3 Chat-Daten und Streaming

- `GET /api/chats` initial laden. Selektiv nachziehen; nicht bei jedem Event kompletten Verlauf laden.
- `GET /api/chats/[id]?messageLimit=...&messageBefore=...` für Pagination. `ETag`/`304` korrekt behandeln.
- `POST /api/chats` zum Erstellen, Server-ID verwenden.
- `POST /api/runs` für Nachrichten bevorzugen, sofern Quellcode-Audit die Semantik bestätigt.
- Bei Nachrichtensendung clientgenerierte `messageId` zur Duplikatvermeidung nutzen. Zusätzlich serverseitige Idempotenz bei unklaren Timeouts implementieren/prüfen.
- `GET /api/runs?...stream=1` verarbeitet SSE inkrementell; **nicht** nur nach einem vollständigen Response-Body rendern.
- SSE-Parser muss geteilte UTF-8-Zeichen, beliebige Chunk-Grenzen, mehrere `data:`-Zeilen, `id`, `event`, Heartbeats/Kommentare und Reconnects korrekt behandeln.
- `Last-Event-ID` bzw. serverseitigen `after`-Cursor je Chat/Job persistieren; bei Reconnect Events nur einmal anwenden. Unterbrochene Streams niemals als abgeschlossene Runs darstellen.
- `GET /api/chats/events` aktualisiert Chatliste und Badge-Zähler; bei Reconnect/Cursor-Lücke gezielter Pull.
- App-Suspension beendet ggf. Streams; bei Foreground **zuerst** Serverzustand synchronisieren, dann neue Streams abonnieren.
- Fehlerzustände differenzieren: offline, Timeout, Server busy (`503/Retry-After`), `401`, `403`, `404`, `409`, Rate Limit, abgebrochener Run.
- Dateivorschau: Remote-Inhalte nur in kontrollierter Vorschau; keine unkontrollierte JavaScript-Ausführung in Chat-Nachrichten.

### 4.4 Datenmodell und UI-State

Empfohlene Domänenmodelle: `ServerProfile`, `Session`, `ChatSummary`, `ChatPage`, `ChatMessage`, `Run`, `RunEvent`, `PendingApproval`, `PendingQuestion`, `MobileNotification`, `MobileDevice`, `ServerCapabilities`.

Schichten:

```text
SwiftUI Views
  ↓
ViewModels / Observable Stores
  ↓
Domain Services (Chat, Runs, Approval, Notification, Voice)
  ↓
MetisAPIClient + SessionStore + SSEClient
  ↓
HTTPS / Cookie Store / Keychain (nur falls erforderlich)
```

Verträge bevorzugt aus einer gemeinsamen serverseitigen OpenAPI-Spezifikation oder aus Zod-Schemas ableiten. Wenn der Codegenerator nicht stabil genug ist, zunächst klar dokumentierte, getestete Swift-DTOs anlegen. **Keine zwei voneinander unabhängigen und still divergierenden Schemas**.

### 4.5 Offline-Verhalten

- Letzte Chatliste und freigegebene Verlaufsausschnitte auf Wunsch lokal zwischenspeichern, mit per-Account-Isolation und Schutzklasse für geschützte Dateien.
- Standardmäßig **keine Geheimnisse, Provider-Keys, Shell-Ausgaben mit Credentials oder sensitiven Attachments dauerhaft cachen**.
- Entwürfe lokal erhalten, optional Nachricht im Outbox-Status „Noch nicht gesendet“. Erst nach bestätigter Serverantwort als gesendet markieren; Replays müssen idempotent sein.
- Entscheidungen **nicht** blind offline vormerken und später ausführen. Für nicht mehr aktuelle Approvals muss neu bestätigt werden.
- Anzeige „Verbindung getrennt“ und manueller Retry, keine Endlosschleifen/Netzwerkflut.

---

## 5. Native Push-Benachrichtigungen (APNs)

### 5.1 Zielereignisse

| Ereignis | Inhalt | Interaktion |
|---|---|---|
| `run.completed` | „Metis hat Aufgabe X abgeschlossen“ | Chat/Ergebnis öffnen |
| `run.failed` | „Aufgabe X ist fehlgeschlagen“ | Fehlerdetails öffnen |
| `approval.requested` | Kurze, redigierte Aktion | Prüfen; nur niedriges Risiko direkt beantworten |
| `question.requested` | Offene Rückfrage | Chat öffnen; optional sichere Textantwort |
| `automation.completed` | Ergebnis einer geplanten Aufgabe | Ergebnis öffnen |
| `agent.attention_required` | Agent braucht Entscheidung | Inbox öffnen |

Inhalt je Nutzer konfigurierbar: Fertigmeldungen, Fehler, Fragen, Genehmigungen, stille Zeit, Vorschau auf Sperrbildschirm (aus/kurz/detailliert). Autorisierung für Benachrichtigungen **erst nach erklärter Nutzenanzeige** anfordern.

### 5.2 Backend-Design

- Wiederverwende **bestehende** Notification Records und Event-Observer, sofern fachlich passend. Der vorhandene WebSocket-Remote-Client-Adapter ist nicht mit APNs gleichzusetzen.
- Neue Tabelle `mobile_devices` (konzeptionell): `id`, `owner_id`, `installation_id_hash`, `platform`, `bundle_id`, `apns_environment`, `apns_token_encrypted`, `token_updated_at`, `enabled`, `created_at`, `last_seen_at`, `revoked_at`. Exakte Typen und Migration an Metis-SQLite-Konventionen anpassen.
- Für deduplizierbare Nachrichten `mobile_push_deliveries`/Outbox mit `notification_id`, `device_id`, `state`, `attempts`, `next_retry_at`, `last_error_code`, `created_at`. **Nicht** den kompletten Push-Text im Fehlerlog ablegen.
- Idempotente `POST /api/mobile/devices`: authentifizierter Account, APNs-Token und Bundle/Environment serverseitig validieren. Gleiches Gerät/Token darf keine Duplikatgeräte erzeugen.
- `GET /api/mobile/devices`: nur **eigene**, redigierte Gerätedaten ohne Token. `DELETE /api/mobile/devices/[id]`: widerrufen.
- Push-Sender: APNs über HTTP/2 mit `.p8`-Signing-Key (`APNS_KEY_ID`, `APNS_TEAM_ID`, Private Key, Bundle/Topic), Sandbox/Production strikt trennen. Entsprechende Secrets gehören in Deployment-Secrets, niemals ins Repo.
- APNs-Statuscodes klassifizieren: Token ungültig/widerrufen -> Gerät deaktivieren; zeitweise Fehler -> Backoff; permanente Fehlkonfiguration -> Alarm/keine Endloswiederholung.
- Zustellgarantie: APNs ist **best effort**, kein exakt-einmaliges oder sofortiges Zustellsystem. Die Inbox/API bleibt Source of Truth.
- Pro Benutzer/Gerät Push-Einstellungen mit expliziter Einwilligung verwalten. Widerruf und Logout müssen Gerätebindung zeitnah entfernen.
- Keine direkten APNs-Requests aus der Next.js-Request-Response-Transaktion. Ereignisse in durable Outbox schreiben und Worker übernimmt Versand.

### 5.3 Beispiel eines datensparsamen Push-Payloads

```json
{
  "aps": {
    "alert": { "title": "Metis benötigt eine Entscheidung", "body": "Eine Aktion wartet auf Prüfung." },
    "category": "METIS_APPROVAL_REVIEW",
    "thread-id": "metis-approvals",
    "sound": "default"
  },
  "v": 1,
  "kind": "approval.requested",
  "resourceId": "opaque-id",
  "serverProfileHint": "opaque-profile-id"
}
```

**Nie enthalten:** Cookies, APNs-Key, Access-Tokens, vollständige User-Prompts, komplette Shell-Kommandos, Datei- oder Gesprächsinhalte, Provider-Secrets. Bei Notification-Tap immer `GET` gegen den Server durchführen und aktuellen Status prüfen.

### 5.4 Aktionen aus der Benachrichtigung

- `UNNotificationCategory` mit z. B. „Öffnen/Prüfen“, „Ablehnen“ und für freigegebene low-risk-Vorgänge ggf. „Genehmigen“.
- `UNUserNotificationCenterDelegate` verarbeitet `didReceive` und ruft **authentifizierten HTTPS-Endpoint** auf; Completion Handler erst nach passender lokaler Bearbeitung, mit Timeout/Fallback.
- `UNTextInputNotificationAction` optional für kurze Agentenfragen: Text wird im jeweiligen authentifizierten Kontext validiert; nicht als generischer unmoderierter Prompt an fremde Resource senden.
- Auf iOS/Watch darf bei verschlossener Session oder Offline-Zustand **nicht** fälschlich „genehmigt“ angezeigt werden. Stattdessen „Aktion nicht ausgeführt – App öffnen“.
- Für Genehmigungen mit Risiken (Shell, Dateien ändern/löschen, externe Veröffentlichung, Remote-Admin, Zahlung, Root, Secrets): Notification öffnet **Detailscreen**, Nutzer sieht vollständige Aktion und bestätigt ggf. mit Biometrie/Passcode.
- „Allow session“ ist standardmäßig **niemals** eine Ein-Tap-Push-Aktion.

### 5.5 Synchronisation und Deduplizierung

- Backendsignale dürfen mehrere Pushversuche auslösen, Nutzer sieht jedoch keine mehrfachen aktiven Tasks.
- Tapping einer alten Benachrichtigung muss „Bereits erledigt/abgelaufen“ statt Doppelaktion zeigen.
- Notification-IDs und Versionsfelder als fachliche Idempotenz-/Concurrency-Key nutzen; keine Entscheidung allein aus `kind` und `resourceId` ohne Serverabfrage.
- Foreground-Websocket/SSE, APNs und manuelle Polls dürfen synchron dasselbe Ereignis verarbeiten, ohne UI-Duplikate.

---

## 6. Entscheidungs- und Sicherheitsmodell

### 6.1 Approval-Lebenszyklus

```text
Agent fordert Tool-Aktion an
    → Metis speichert PendingApproval + Version + Owner + Kontext
    → Benachrichtigung wird erzeugt und über APNs verschickt
    → iPhone/Watch lädt aktuelle Details authentifiziert
    → Nutzer genehmigt/verbietet (ggf. starke Bestätigung)
    → Metis führt die bestehende resolveActionApproval-Logik aus
    → Pending-Status atomar geändert; Agent wird serverseitig fortgesetzt
    → alle Clients sehen denselben finalen Status
```

**Serverseitige Pflichtprüfungen:**

- Identität, Tenant/User und Besitzrecht zum konkreten Chat/Job.
- Berechtigung zum betreffenden Tool und Risiko-/Scope-Klasse.
- Approval-ID + Version + Pending-State + Ablaufzeit.
- Atomare CAS-Entscheidung („first successful resolution wins“), keine Wiederholung nach App-Retry.
- Audit-Event mit Actor/Device, Entscheidung, Zeit und referenziertem Job, **ohne unnötigen Secret-/Promptinhalt**.
- Beibehalten der vorhandenen `resolveActionApproval`-Regeln; keine neue zweite Entscheidungsengine.

### 6.2 Risikoklassen

| Klasse | Beispiele | Mobile-Aktion |
|---|---|---|
| **R0 Information** | Run fertig, Status | Anzeigen / öffnen |
| **R1 Niedrig** | Klar begrenzte, reversible Freigabe | Nach Opt-in aus Push möglich, ansonsten in App |
| **R2 Mittel** | Schreiben, externe Integration, Dateiveränderung | Nur in App mit sichtbarem Kontext und expliziter Bestätigung |
| **R3 Hoch** | Root, Löschen, kritische Systemaktionen, Secret-Zugriff, remote Admin | Kein direkter Push-/Watch-One-Tap; frische Auth-/Biometrieprüfung, optional Desktop-only |

Die Klassifizierung muss **am Server** anhand tatsächlicher Tool-Metadaten erfolgen, nicht anhand einer LLM-Beschreibung. Bis eine belastbare Klassifizierung existiert: alle `allow`-Aktionen nur in der App nach ausführlicher Prüfung.

### 6.3 Agenten-Rückfragen

Die bestehende `POST /api/chat/answer`-Logik soll wiederverwendet werden. Antworten auf mehrteilige Fragen/Formulare benötigen das vollständige native Formular; auf der Watch nur einfache Antworten bzw. Übergabe aufs iPhone. Validierung und Version/Statuskonflikt ausschließlich serverseitig entscheidend.

---

## 7. Apple Watch

### 7.1 Geplante Watch-Ansichten

- **Start:** „Metis verbunden“, aktive Runs, Anzahl wartender Entscheidungen.
- **Entscheidungen:** Liste offener Items → Details (kurz und verständlich) → Ablehnen oder – bei erlaubtem Risikoprofil – Genehmigen.
- **Neuer Prompt:** Sprach-/Diktat- oder Texteingabe → Chat auswählen/neu → sichtbar bestätigen → senden → serverseitige Empfangsbestätigung.
- **Aktivität:** laufende oder zuletzt abgeschlossene Jobs; kurze Textvorschau.
- **Status:** Server erreichbar? iPhone verbunden? Wann zuletzt synchronisiert?

### 7.2 Verbindung iPhone ↔ Watch

**Default V1:** Companion-Watch-App über `WatchConnectivity`:

- `sendMessage` für **unmittelbare** Aktionen, nur wenn Gegenstelle `isReachable` ist.
- `updateApplicationContext` für letzten Status/Snapshot.
- `transferUserInfo` für verlässliche, aber möglicherweise verspätete kleine Statusinformationen.
- Watch erhält keine permanenten iPhone-Session-Cookies oder Provider-Keys.
- Eine Watch-Aktion wird durch iPhone an Metis weitergeleitet und **erst nach Serverbestätigung** als erfolgreich markiert.
- Ist das iPhone nicht erreichbar, Aktion sichtbar als „noch nicht gesendet“ markieren. Für kritische Approvals **nicht** im Hintergrund später ausführen.

**V2 optional:** Eigenständige Watch-HTTPS-Anbindung mit **kurzlebiger, gerätespezifischer, widerrufbarer und stark eingeschränkter Session**. Diese braucht eigenes Pairing, sichere Speicherung, Access-Control und zusätzliche Sicherheitsprüfung. Nicht als Voraussetzung für V1.

### 7.3 Spracheingabe

- Primär systemeigene Watch-Diktier-/Texteingabe, die auf der jeweiligen watchOS-Version unterstützt wird.
- Nutzer sieht transkribierten Prompt **vor** dem Absenden und kann ändern/abbrechen.
- Optional später AVAudio-/Servertranskription für Fälle, in denen Diktat nicht genügt; Watch-Mikrofon nur nach expliziter Nutzeraktion mit benötigten Privacy-Strings.
- Nie unbemerktes oder dauerhaftes Mithören. Netz-/Diktatfehler benutzerverständlich erklären.

### 7.4 Apple Watch Series 3: kritischer Compatibility-Gate

**Fakt:** Series 3 unterstützt höchstens **watchOS 8.8.1** (Apple-Support). Laut Apple SDK-Tabelle unterstützt **Xcode 27 watchOS 9 als niedrigstes Deployment-Target**, **Xcode 26.6 watchOS 8**.

Daraus folgt:

1. **Series-3-Support nicht ungeprüft versprechen.** Ein modernes watchOS-9+-Target würde diese Watch ausschließen.
2. Vor Architekturfixierung ein minimal funktionsfähiges SwiftUI-Watch-Testprojekt für watchOS 8 mit der verfügbaren Xcode-Version kompilieren, signieren, auf eine echte Series 3 installieren und die **aktuell von App Store Connect akzeptierte Upload-Toolchain** bestätigen.
3. Vergleiche technische Einschränkungen von watchOS 8 (SwiftUI-APIs, TextInput, Speicher/Performance, Pairing mit aktueller iPhone-iOS-Version, Notification-Verhalten).
4. Bevorzugt **ein** wartbares Watch-Target, sofern Series 3 realistisch einbeziehbar ist.
5. Falls nicht: modernes watchOS-Target für spätere Watches **plus** native iPhone-Pushes mit System-Notification-Mirroring auf Series 3 als Fallback. Den Kompromiss klar dokumentieren; nicht auf App-Review-Richtlinien oder unsignierte Legacy-Builds wetten.
6. Keine watchOS-27-only Frameworks im gemeinsamen Watch-Code verwenden, solange Legacy-Support als Ziel existiert.

**Abnahmekriterium:** Ein auf echter Series 3 nachweislich installierbarer, per Diktat und Entscheidung testbarer Watch-Build **oder** dokumentierter No-Go samt verifiziertem iPhone-Mirroring-Fallback.

---

## 8. Kontrollierter iPhone-Zugriff: Device Capabilities

Metis bekommt keinen generellen Root-/Shell-/Dateisystemzugriff auf iOS. Stattdessen wird ein **Capability-Adapter** pro Apple-Framework mit Nutzerzustimmung implementiert.

| Capability | Implementierungsweg | Grenze/Policy |
|---|---|---|
| Foto auswählen | `PhotosPicker` | explizit ausgewählte Assets, nicht gesamte Galerie |
| Kamera | `AVFoundation` oder systemischer Picker | Permission + aktive UI, keine stille Kameraüberwachung |
| Dateien | `fileImporter`/Document Picker/Share Extension | nur Dateien, die Nutzer auswählt/teilt |
| Sprache | Diktat / Mikrofon/Transkription | sichtbare Aufnahme + Permission |
| Kalender | `EventKit` | Benutzerpermission und klare Aktion/Bestätigung |
| Kontakte | `Contacts` | gezielter Zugriff, keine massenhafte Exfiltration |
| Standort | `CoreLocation` | optional, „when in use“, keine unnötige Hintergrundortung |
| Kurzbefehle/Siri | `App Intents` | definierte Metis-Aktionen, kein allgemeines Device-Control |
| Share Sheet | Share Extension | ausgewählten Text/URL/Bild an Metis übergeben |
| Widgets/Live Activities | WidgetKit/ActivityKit bei geeigneten OS-Zielen | systembedingte Update-/Energiegrenzen |
| Notifications | UserNotifications/APNs | permissionbasiert, keine garantierte Sofortzustellung |

**Capability-Design:**

1. Funktion im Settings-Screen einzeln aktivierbar.
2. Berechtigung nur „just in time“ bei Nutzeraktion anfragen.
3. Vor jedem Transfer zeigen, **welche Daten an welchen Metis-Server** gesendet werden.
4. Für schreibende Aktionen (Kalendereintrag, Kontaktänderung, Dateioperation) eine sichtbare Bestätigungsansicht anbieten; besonders sensible Vorgänge nicht automatisieren.
5. Nur explizit genehmigte Objekte/Scopes übertragen; nicht ganze Fotobibliotheken/Kontaktdatenbanken scannen.
6. Serverseitige Agentenausgaben niemals als dynamischen Swift-Code oder private iOS-API-Aufrufe ausführen.
7. Dateien nach Bedarf löschen; Aufbewahrungs- und Löschkonzept dokumentieren.
8. Jede Capability muss mit fehlender Berechtigung, abgebrochener Auswahl, Offlinezustand und widerrufenen Berechtigungen umgehen.

**Empfehlung für v1:** Fotos/Kamera/Dateien/Sprache. `App Intents` und Share Extension danach. Kalender/Kontakte/Standort nur wenn dafür ein konkretes Produktfeature und eine belastbare Datenschutzbegründung vorliegen.

---

## 9. API-Design und Verträge für Mobile

Bestehende APIs **nicht brechen**. Neue Routen nur, wo wirklich notwendig. Vorgeschlagene mobile API: Bezeichnungen sind **Plan**, noch keine vorhandenen Routen.

### 9.1 Capabilities und Versionierung

`GET /api/mobile/capabilities` (neue Route)

```json
{
  "apiVersion": 1,
  "minSupportedClientVersion": "1.0.0",
  "features": {
    "chat": true,
    "sseRuns": true,
    "apns": true,
    "approvals": true,
    "questions": true,
    "voiceTranscription": true,
    "watchRelay": true
  },
  "limits": { "maxUploadBytes": 0 },
  "serverVersion": "provided-by-server"
}
```

`maxUploadBytes=0` ist nur ein **Schema-Platzhalter** und muss durch den realen Serverwert oder `null` ersetzt werden; niemals als faktisches Limit ausgeben. API-Version per Feature-Negotiation und additive Änderungen pflegen. Bei älteren Servern ohne diesen Endpoint mittels klar definierter Feature-Discovery oder kompatibler Fehlermeldung arbeiten.

### 9.2 Geräte registrieren

`POST /api/mobile/devices`

```json
{
  "installationId": "random-opaque-installation-id",
  "platform": "ios",
  "bundleId": "configured.bundle.id",
  "apnsEnvironment": "sandbox",
  "apnsToken": "device-token-from-system",
  "notificationSettings": {
    "runFinished": true,
    "approvals": true,
    "questions": true,
    "errors": true
  }
}
```

Antwort: `{ "deviceId": "opaque-id", "registered": true }` — genaue, mit Tests fixierte Contract-Fassung. Jede Änderung authentifiziert und `owner_id` ausschließlich aus der Session, nie aus Client-Body. `apnsToken` nur während der Übertragung im Request, Speicherung geschützt; Responses/Logs ohne Token.

### 9.3 Mobile-Aktionen

Ein neuer `POST /api/mobile/actions/[id]` ist nur dann nötig, wenn der bestehende `POST /api/chat/approval` nicht ausreichend mobile-sicher ist. **Bevorzugt Adapter, kein Fork**:

```json
{
  "type": "approval.decision",
  "decision": "deny",
  "expectedVersion": 3,
  "idempotencyKey": "random-uuid"
}
```

Der Server mappt auf die bestehende Approval-Logik, prüft Owner/Scope, Risikoklasse, stale-State und dedupliziert `idempotencyKey`. Antwort enthält endgültigen Status und optional `chatId`. Kein Vertrauen auf die Risikoeinstufung vom Client.

### 9.4 Fehlercontract

Fehler als stabiler Code (`unauthorized`, `invalid_input`, `stale_action`, `already_resolved`, `forbidden`, `rate_limited`, `server_unavailable`) plus menschenlesbarer Text. HTTP-Status beibehalten. Niemals Interna, Stacktraces oder Secrets an den Client schicken.

### 9.5 API-Dokumentation

- Für jeden genutzten Endpunkt Request, Response, Feldtypen, Auth, Pagination, Fehler, Max-Limits, Rate-Limits, Beispiel und zugehörigen Test dokumentieren.
- Contract Tests gegen den **echten Metis-Handler**, Swift-Decoder gegen gespeicherte Fixtures.
- Neue optionalen Felder müssen vorwärts-/rückwärtskompatibel eingeführt werden.
- Existierende Web-SSE-Consumer und Remote-Clients mit Regressionstests absichern.

---

## 10. Authentifizierung, Datenschutz, Threat Model

### 10.1 Threat Model

Angreifer-Szenarien: gestohlenes/gesperrtes iPhone, abgefangene Push-Vorschau, verlorene Watch, kompromittierte Geräte-Token, wiederholter Approval-Request, Cross-User-Zugriff, CSRF gegen Cookie-APIs, DNS-/TLS-Spoofing, nicht vertrauenswürdiger Metis-Server, Prompt Injection in Agent-Tool-Ausgaben, Push-Spam, auslaufende Legacy-App-Versionen.

**Schutzmaßnahmen:**

- TLS mit Standardvalidierung und ATS, keine privaten Zertifikate stillschweigend akzeptieren. Entwicklungs-Ausnahmen getrennt vom Production-Build.
- Schutz der Session-Cookies, kein Logging des `Cookie`-Headers; angemessenes Cookie-Handling in `URLSession`.
- CSRF-/Origin-Schutz der vorhandenen API überprüfen, ohne den legitimen nativen Client zu blockieren; keine statischen Shared-Secrets in App-Binary als „Sicherheit“.
- Server-Owner-/Rollenprüfungen bei **jedem** Chat, Run, Upload, Approval, Notification und Device-Lookup.
- Getrennte Profile bei mehreren Metis-Instanzen, Credentials/Cache strikt isoliert.
- Logout/Passwortwechsel widerruft Sessions. Device-Revocation als eigener Vorgang, da APNs-Tokens keine Metis-Login-Tokens sind.
- Keine serverseitigen Provider-/MCP-/Root-Secrets auf dem iPhone.
- Biometrie ist **lokale zusätzliche UX-Schutzschicht**, kein Ersatz für Server-Auth und Autorisierung.
- Notification-Snippets redigieren, optional komplett privat auf Lockscreen.
- Agenten-Prompts/Outputs als **untrusted content** behandeln. Keine automatischen lokalen Geräteaktionen allein wegen LLM-Anweisung.
- Multi-User-Isolation und Team-/Projektberechtigungen mit Negativtests absichern.
- Session-Fixation, Redirects, Replay, Double-Tap, Race Conditions und Offline-Replays testen.

### 10.2 Datenschutz- und App-Store-Pflichten

- Datenschutzerklärung mit realen Datenflüssen (Metis-Server, APNs, Modell-Provider, ggf. Transkriptionsanbieter), Speicherorten und Löschmöglichkeiten.
- App Privacy Nutrition Labels anhand tatsächlichem Verhalten ausfüllen; nicht pauschal „keine Daten“, wenn Chats oder Metadaten übertragen werden.
- Berechtigungs-Texte für Kamera, Mikrofon, Fotos, Kalender/Kontakte/Standort nur für aktivierte Funktionen.
- Konto-Löschung in der App prüfen/implementieren, falls Kontenerstellung in der App möglich ist oder die aktuellen Review-Regeln es verlangen; Datenlöschung und Account-Abmeldung sauber trennen.
- Bei geteilter/öffentlicher KI-Content-Funktion die **App-Review-Anforderungen für User-Generated Content/AI-Inhalte** bewerten (z. B. Melden/Blockieren/Moderation); Funktionen und App-Store-Listing korrekt beschreiben.
- Falls künftig digitale Abos/Features in der App verkauft/freigeschaltet werden, Apple-IAP-/Regionenregeln separat prüfen. Für den ersten Release keine unklaren externen Zahlungsflüsse einbauen.

### 10.3 Besonderheit Self-Hosting

Ein öffentlich gelisteter nativer Client für selbst gehostete Server sollte beim ersten Start das Server-Setup klar erklären. **App Review benötigt einen funktionierenden, sicheren Testserver mit Demo-Account** oder eine von Apple akzeptierte Demo-Lösung. Kein Apple-Reviewer kann sich auf einen privaten Heimserver verlassen. Der iOS-Client muss eigenständige native Funktionen bieten, nicht nur ein Browser-Wrapper sein.

---

## 11. UI/UX-Anforderungen und Barrierefreiheit

- Systemdesign mit SwiftUI, dynamischer Schriftgröße, VoiceOver, Dark/Light Mode, ausreichenden Touch-Flächen.
- iOS 27 visuell modern, aber Deployment-Target nicht unnötig auf iOS 27 festlegen.
- Saubere Fehlermeldungen ohne Dev-Jargon; sichtbare Zustände für `queued`, `running`, `waiting_for_user`, `completed`, `failed`, `interrupted`.
- Lange Chats und Codeblöcke flüssig scrollen; Syntax-Highlighting darf keinen UI-Freeze verursachen.
- Lokalisierungsfähige Strings (mindestens Deutsch und Englisch), kein Hardcoding in ViewModels.
- Native `ShareLink`, Dateiauswahl, Copy-to-Clipboard nur für ausdrücklich ausgewählte Inhalte.
- Notification-Tap navigiert über einen zentralen Deep-Link-Router direkt zur betroffenen Chat-/Decision-Ansicht.
- Nach einem riskanten Approval im App-Screen komplette Tool-Beschreibung, betroffenen Pfad/Ziel und Risiko sichtbar; nicht allein auf Titel vertrauen.

---

## 12. App-Store-/Apple-Developer-Strategie

### 12.1 Konten und Kosten

- Apple Developer Program: derzeit **99 USD/Jahr** bzw. lokaler Betrag; 2FA und erforderliche Volljährigkeit für den bezahlten Vertrag.
- In Deutschland ist **kostenlose Apple-Developer-Registrierung ab 16** möglich; der zahlungspflichtige Program-Vertrag setzt die **gesetzliche Volljährigkeit** voraus. Falls Inhaber noch minderjährig: Veröffentlichung über einen rechtmäßig berechtigten volljährigen Account-/Organisationsinhaber. Zugänge/Signierung über Apple-Rollen verwalten, keine Accounts „ausleihen“ oder falsche Identitätsdaten verwenden.
- Bundle ID, App Name, Team, Signing Certificates/Profiles und APNs Auth Key erst mit dem berechtigten Apple-Team finalisieren.
- TestFlight und öffentliche Distribution benötigen passende Program-Mitgliedschaft und App Store Connect.

### 12.2 Build-Konfiguration

- `Debug`: frei wählbare lokale Testserver, keine Produktions-Keys, APNs Sandbox, klar markiert.
- `Staging`: vertrauenswürdiger HTTPS-Testserver, Sandbox/TestFlight entsprechend Signatur-/Environment-Verhalten.
- `Release`: Production-Signing, Production-APNs, keine Debug-Logins, keine beliebigen TLS-Ausnahmen.
- Secrets ausschließlich im Apple-Team, CI-Secrets-Store und Metis-Deployment-Secrets.
- Supported Deployment-Target für iOS bewusst festlegen (z. B. iOS 17+ nach API-/Device-Audit); Series-3-/watchOS-8-Frage **separat** behandeln.

### 12.3 App Store Review

- Guideline 4.2: native Mehrwerte: SSE-Chat, Push-Aktionen, Watch, Share Sheet, Diktat/App Intents.
- Guideline 2.1: vollständig funktionierender Demo-Account/HTTPS-Demo-Server, Reviewer kann Chats, Runs und Push-Aktionen reproduzieren.
- Geschäftsmodell klar kommunizieren: „Client für selbst gehostete Metis-Instanzen“; keine falschen Versprechen einer kostenlosen, vom Entwickler gehosteten KI-Infrastruktur.
- Transparente Erklärung der AI-Provider-Abhängigkeiten und serverseitigen Ausführungsmöglichkeiten; keine versteckten Funktionen.
- App-Store-Metadaten: Screenshots auf unterstützten Geräten, Icon, Datenschutz-URL, Support-URL, Altersfreigabe, Sprachen, Demo-Zugang, App-Review-Notizen und ein kurzes Testskript.
- Vor Upload aktuelle **SDK-Mindestanforderungen** von Apple erneut nachsehen. Dies betrifft insbesondere ältere Watch-Builds.

---

## 13. Implementierungsphasen mit konkreten Tickets

Jede Phase ist ein eigener PR-geeigneter Meilenstein. In der Checkliste bezeichnet „fertig“ ausschließlich nach Tests validierte Arbeit.

### Phase A — Repository-Audit und technische Spike-Tests

- [ ] Repo/Branch/Contributing/Security lesen; aktuellen HEAD pinnen.
- [ ] API-Inventar für Chat, Runs, SSE, Auth, Files, Voice, Approval, Questions, Notifications erstellen.
- [ ] Auth und Cookie-Sessions aus nativem `URLSession` gegen isolierte lokale Testinstanz verifizieren.
- [ ] Echten Run-Event-Stream mit Cursor/Reconnect analysieren; Fixture-Katalog erzeugen.
- [ ] APNs-Signing-/Device-Registrierung designen; Security-/Privacy-Review.
- [ ] SwiftUI-iOS-Projekt bootstrappen und auf realem iPhone bauen.
- [ ] watchOS-8-/Series-3-Kompatibilitäts-Spike inklusive App-Store-Build-Anforderungen durchführen; Entscheidung dokumentieren.
- [ ] `docs/APPLE-API-INVENTORY.md`, Architekturentscheidung und Backlog festhalten.

**Abnahme:** Keine offenen, stillschweigend geratenen API-Contracts; mindestens iPhone-Projekt startet mit Test-Screen; Watch-Entscheidung belegbar.

### Phase B — iOS-Basisschicht

- [ ] App-Target, Shared-Modul, Build-Konfiguration und README.
- [ ] `ServerProfileStore`, URL-Validierung und erste Verbindung.
- [ ] Login/Logout gegen echte Metis-Auth; `URLSession`-Cookie-Verhalten testen.
- [ ] Auth-Fehler, Session-Rotation, 401-Neuanmeldung, Serverwechsel.
- [ ] `MetisAPIClient` mit einheitlichen Timeouts/Fehlern/DTOs und Rate-Limit-Behandlung.
- [ ] UI-Tests für Onboarding/Anmeldung/Server offline.

**Abnahme:** Nutzer kann sich anmelden/abmelden; Cross-Server-/Cross-User-Daten treten nicht aus; keine unsichere TLS-Ausnahme im Release.

### Phase C — Chat-MVP

- [ ] Chatliste laden, aktualisieren, paginieren/suchen sofern API unterstützt.
- [ ] Chat erstellen und öffnen; Nachrichtenseiten nachladen.
- [ ] Nachricht senden via bestehende Run-Pipeline; stabile `messageId`.
- [ ] SSE-Run-Streaming und Chat-Sync-Cursor.
- [ ] UI für Markdown, Code, einfache Attachments und Run-Status.
- [ ] Cancel/Resume; Pending-Question/Approval mindestens als sichere „auf iPhone öffnen“-Karte.
- [ ] Reconnect/Offline/Background-Foreground-Tests.

**Abnahme:** Auf iPhone erstellter Chat erscheint im Web und umgekehrt; ein echter Agentenlauf streamt; nach Netzabbruch kein Nachrichtenverlust/Double-Send.

### Phase D — Push-Infrastruktur

- [ ] SQLite-Migration für Devices und Push-Outbox mit Indexen.
- [ ] Owner-isolierte Device-Routen + Validierung + sichere Aufbewahrung.
- [ ] APNs-Provider mit HTTP/2/JWT, Sandbox/Production und Retry-/Revocation-Handling.
- [ ] Integration mit bestehendem Notification-/Run-Event-Modell; deduplizieren.
- [ ] iPhone-Berechtigungsanfrage, Tokenregistrierung und Subscription-UI.
- [ ] Run-completed/error/approval/question Push-Payloads + Notification Routing.
- [ ] Tests für APNs-Fehler, Device-Revocation, Accountwechsel, Spam-/Rate-Limits.

**Abnahme:** Echter Push kommt bei beendeter iPhone-App auf Testgerät an; bei deaktivierter Permission/Offlinezustand bleibt der Serverfeed korrekt.

### Phase E — Sicherheitsfreigaben und Agentenfragen

- [ ] Native Pending-Approval-Details mit tatsächlichem Tool-Kontext.
- [ ] Risikopolicy serverseitig, konservativer Default.
- [ ] Bestehende Approval-API/Flow weiterverwenden, `version` und Idempotenz sicherstellen.
- [ ] Approval/Reject-Push-Action für erlaubte Klassen; riskante Schritte nur in App.
- [ ] Biometrie-Check in App als Zusatz für R2/R3, keine Security-Bypass-Fallbacks.
- [ ] Text-/Form-Antworten auf Pending-Questions.
- [ ] Race-/Replay-/Wrong-User-/Stale-Approval-Tests.

**Abnahme:** Genau eine finale Entscheidung; alle Clients spiegeln den gleichen Status; R3 ist nicht versehentlich als One-Tap-Aktion möglich.

### Phase F — iOS-Produktfunktionen

- [ ] Bild-/Dateiupload mit MIME-/Größenprüfungen und sauberem Cleanup.
- [ ] Sprachprompt/Diktat und, wenn notwendig, serverseitige Transkription.
- [ ] Modellauswahl und Projekte/Agenten-Übersicht gemäß API-Audit.
- [ ] Notification-Einstellungen, lokale Vorschau-Präferenzen und Profil.
- [ ] Chat-Suche, Archivierung, Pinned Chats, Links/Attachments.
- [ ] i18n, Dynamic Type, VoiceOver, Performance-/Memory-Profiling.

**Abnahme:** Standardalltag aus der Web-App ist mobil ohne Browser nutzbar; komplexe Funktionen haben eindeutige Fallbacks.

### Phase G — Watch-App

- [ ] Watch-Target nach Compatibility-Gate anlegen.
- [ ] WatchConnectivity pairing, aktiv/reachability, Status-Snapshot.
- [ ] Offene Approvals/Questions listen, Details anzeigen, sichere Entscheidung mit Serverquittung.
- [ ] Watch-Prompt per Texteingabe/Diktat und Chat-Auswahl.
- [ ] Watch-Notifications: zeigen, öffnen, verfügbare Actions sicher behandeln.
- [ ] Offline/nicht erreichbar/Watch neu gestartet/Telefon gesperrt testen.
- [ ] Physisches Testgerät, falls Series 3 als supported ausgewiesen wird.

**Abnahme:** Kurzer Prompt erreicht richtigen Metis-Chat; Entscheidung wird erst nach erfolgreichem Server-ACK als erledigt markiert; kein Auth-Secret auf der Watch.

### Phase H — iPhone-Integrationen

- [ ] Fotos, Kamera, Files/Share Sheet mit Datenvorschau.
- [ ] App Intents: „Prompt an Metis senden“, „Offene Entscheidungen öffnen“, „Status meiner Runs“.
- [ ] Optional Kalender-/Kontakte-/Standort-Adapter, jeweils dokumentierter Datenfluss und Permission.
- [ ] Geräte-Capability-Settings, Revocation und Tests.
- [ ] Optional Widgets/Komplikationen und Handoff.

**Abnahme:** Jede Integration funktioniert nur mit erlaubter Nutzeraktion; erweiterte systemweite Steuerung wird nicht vorgetäuscht.

### Phase I — Release Engineering

- [ ] iOS-/Watch-Unit-Tests, UI-Tests, Node-Tests, Regressionstests, API-Contracts.
- [ ] Accessibility, Stress- und lange-Chat-Tests; Offline/Push/Logout/Accountwechsel.
- [ ] Secret Scan, Threat-Model-Review, TLS-/CSRF-/CORS-/Owner-Isolation-Audit.
- [ ] Apple Signing, Entitlements, Bundle IDs, APNs Keys getrennt nach Environment.
- [ ] TestFlight-Archiv, externer Test auf realen Geräten, Crash-/Telemetry-Review.
- [ ] Privacy Policy, App-Store-Listing und funktionsfähige Review-Demo.
- [ ] Manuelle Freigabe zur Einreichung einholen (kein automatischer Public Release).

**Abnahme:** Alle Release-Gates grün; reproduzierbarer, signierter Release-Build; keine offenen Critical/High-Security-Bugs.

---

## 14. Tests: konkrete Matrix

| Testfall | Nachweis |
|---|---|
| iPhone ↔ Web Chat-Synchronisierung | Beide Clients zeigen identische IDs/Status, keine Doppelmessages |
| 50+ Chat-Events / langer Verlauf | Scrollen/Pagination ohne UI-Blockade; keine flächigen Refetches |
| Unterbrochener SSE-Stream | Reconnect mit Cursor, keine verlorenen/duplizierten Events |
| Nachricht gesendet, HTTP-Response verloren | Retry produziert höchstens eine Nachricht/einen Job |
| Server offline, Session abgelaufen | Saubere Fehler- und Loginzustände; keine unbemerkte Wiederholung |
| Cross-User-/Cross-Project-Zugriff | Fremde IDs liefern 403/404, auch in Device-/Push-/Approval-Routen |
| APNs Sandbox/Production | Passender Topic/Token; falsche Umgebung wird nachvollziehbar abgefangen |
| Push-Token-Rotation/Logout | Altes Gerät keine zukünftigen sensiblen Pushes; erneute Anmeldung sauber |
| Push kommt doppelt/verspätet | Nur eine finalisierte Entscheidung; alte Actions zeigen stale state |
| Zwei Clients bestätigen denselben Vorgang | Atomare First-Wins-Entscheidung |
| Watch ohne iPhone-Reichweite | Keine erfundenen Erfolgsanzeigen, keine spätere unbemerkte Genehmigung |
| Watch-Diktat: Abbruch / falscher Chat | Kein Senden ohne sichtbaren Commit |
| Kamera/Fotos/Files permission denied | App bleibt nutzbar; erklärt Funktion und Settings |
| Wechsel zwischen zwei Metis-Servern | Kein Credential-/Chat-/Cache-Leak zwischen Instanzen |
| Hintergrund/Force Quit/Low Power Mode | Push/Sync entsprechend Apple-Limits, korrekte Resync bei Vordergrund |
| Notification Lock Screen | Keine Secrets, keine vollständigen Tool-Befehle im Klartext |
| User-Generated/AI-Inhalte | Review-relevante Sicherheits- und Meldeprozesse bewertet |

**Minimum automatisierte Suite:** Server: `pnpm typecheck`, `pnpm lint`, gezielte Tests plus `pnpm test` soweit ausführbar; Apple: `xcodebuild build`, `xcodebuild test` auf unterstützten Simulatoren, separate echte Geräte-/APNs-/Watch-Tests mit protokollierten Ergebnissen. Kein „Tests bestehen“ behaupten, wenn nur Code statisch inspiziert wurde.

---

## 15. CI/CD und Release-Sicherheit

- GitHub Actions macOS-Runner für iOS-/Watch-Build/Test, Node-Runner für Backendtests, falls Projektkonventionen passen.
- PR-Checks ohne Production-Signing; signierte TestFlight-/App-Store-Archive nur auf explizit freigegebenen Release-Tags/Workflows.
- Keine private `.p8`-Datei als CI-Artifact oder im Git-Verlauf; Key aus gesichertem Secret-Store im isolierten Runner bereitstellen.
- Release-Changelog und Migrationshinweise für Serverbetreiber.
- APNs-Konfiguration dokumentieren: Team ID, Key ID, Bundle ID, Topic, Environment, Transport, Outbound-443-Zugriff.
- Feature Flags für Push, Approval-Actions, Watch-Relay, App Intents; falls Fehler auftreten, serverseitiges Abschalten ohne App-Update.
- Monitoring: anonymisierte Zustellversuche, Rate-Limits, 401-/409-Quoten, Run-SSE-Reconnects, Geräte-Registrierungsfehler. Keine Chat-Inhalte oder Tokens im Standardmonitoring.
- Versionsmanagement: mobile App darf älter als Server sein; API wird additiv erweitert, nicht abrupt umgestellt. Deprecation erst nach Nutzungsanalyse.

---

## 16. Offene Produkt-/Architekturentscheidungen (Codex soll Vorschläge machen, nicht blind raten)

| Frage | Startentscheidung | Gate |
|---|---|---|
| Name/Bundle ID | Arbeitsname „Metis“, Bundle ID erst mit Apple-Team fixieren | Apple-Team |
| iOS Deployment Target | Möglichst breit, z. B. iOS 17+, nach API-Audit | Xcode-Tests |
| Series-3-Support | Verifikationspflicht; ggf. Mirroring-Fallback | realer Watch-Test + Apple Upload-Regeln |
| Login | Metis-Web-Account/Cookie wiederverwenden | Session-/CSRF-Audit |
| Mehrere Server | zunächst ein aktives Profil; Datenmodell erweiterbar | Privacy-/Migrationstest |
| Watch-Kommunikation | iPhone-Relay via WatchConnectivity | echte Reichweitentests |
| Watch-Standalone | nicht V1 | zusätzliche sichere Sessionarchitektur |
| Push-Freigabe | konservativ: Review in App; später R1-One-Tap per Opt-in | Risk-Policy-Audit |
| Server-Push | direktes APNs mit durable Outbox | Versand- und Retry-Tests |
| Push bei privatem Homelab | Server braucht ausgehendes APNs-Netz; öffentlicher HTTPS-Zugang für mobilen Client, nicht offenes MCP | Netz-/Security-Setup |
| Voice | iOS systemeigene Diktieroption, vorhandene Server-Transkription optional | API-/UX-Test |
| Monetarisierung | keine In-App-Purchases in V1 | App-Review-Prüfung |
| App-Store-Demo | separater, stabiler HTTPS-Demo-Server mit Fake-Daten | Review-Test |

**Besonders wichtig:** Nutzer kann einen privaten, selbst gehosteten Metis-Server betreiben. Für iPhone außerhalb des Heimnetzes ist ein sicher erreichbarer HTTPS-Endpunkt oder eine bewusst konfigurierte VPN-Verbindung nötig. Den MCP-Port, SSH oder eine ungeschützte Metis-Installation **niemals** allein für die App offen ins Internet stellen. APNs selbst benötigt nur ausgehenden Versand vom Server und kann keine fehlende Client-API-Erreichbarkeit ersetzen.

---

## 17. Definition of Done (gesamt)

Ein Release gilt erst als abgeschlossen, wenn:

- [ ] iPhone-App kann sich mit einer echten Metis-Instanz sicher anmelden.
- [ ] Web und Mobile arbeiten mit denselben Chat-/Run-/Userdaten.
- [ ] Laufende Agenten streamen sichtbar und lassen sich sicher abbrechen.
- [ ] Offline-/Reconnect-Szenarien führen nicht zu unbeabsichtigten Wiederholungen.
- [ ] APNs-Push funktioniert auf realem iPhone mit nicht geöffneter App.
- [ ] Freigaben/Fragen sind vollständig ownergebunden, versionsgeprüft und idempotent.
- [ ] Keine riskante Tool-Aktion ist über eine unsichere Push-/Watch-Abkürzung ausführbar.
- [ ] Mindestens eine getestete Watch-Strategie samt Series-3-Entscheidung vorliegt.
- [ ] Mikrofon/Kamera/Fotos/Dateien sind optional und korrekt permissiongebunden.
- [ ] Backend-, iOS-, Security- und reale Gerätests dokumentiert sind.
- [ ] Signierung, TestFlight, Review-Demo und App-Privacy-Unterlagen vorbereitet sind.
- [ ] Bestehende Metis-Web-Clients und Remote-Clients keine Regression zeigen.
- [ ] Der Apple-Account-Inhaber die Veröffentlichung ausdrücklich genehmigt hat.

---

## 18. Priorisierte erste Codex-Arbeitseinheit

**Direkter Startauftrag (ohne weitere Rückfragen zur Architektur):**

1. Repo `f1shyondrugs/metis` auf aktuellem Branch analysieren und die hier genannten Handler/Schemas verifizieren.
2. `docs/APPLE-API-INVENTORY.md` und `docs/APPLE-CLIENTS-IMPLEMENTATION.md` erstellen.
3. iOS-Xcode-Projekt in `clients/apple` mit kompilierbarer SwiftUI-App, einfacher Server-URL-Eingabe und einer echten Authentifizierungs-/Sessionprüfung anlegen.
4. Einen isolierten Testserver-/Mock-Modus einrichten, der **keine echten Secrets** benötigt.
5. Minimalen Chat-Read-Only-Flow (Liste und Detailansicht) gegen vorhandene API mit Tests bauen.
6. Erkenntnisse zum Series-3-/watchOS-8-Kompatibilitätsgate als klaren Bericht festhalten, bevor Watch-Code entsteht.
7. Erst danach Chat-Senden/Streaming als nächstes geschlossenes Feature implementieren.

**Abschlussbericht der ersten Arbeitseinheit:**

```markdown
## Ergebnis
- Branch und Commit:
- Geänderte Dateien:
- Genutzte vorhandene Metis-APIs:
- Neue Routen und Migrationen (falls nötig):
- Build-/Testkommandos und tatsächliche Ergebnisse:
- Manuell zu prüfende Schritte:
- Risiko-/Security-Feststellungen:
- Series-3-/Watch-Entscheidung:
- Nächster konkreter Implementierungsschritt:
```

Keine „fertig“-Markierung ohne Nachweis. Bei fehlendem Xcode, Signierung, physischer Watch oder Apple-Developer-Zugang nur die in der Umgebung möglichen Arbeiten ausführen und echte Geräte-/App-Store-Tests ausdrücklich als **nicht durchgeführt** markieren.

---

## 19. Offizielle Apple-Quellen (Stand 03.11.2026)

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — besonders 1.2 (UGC/AI), 2.1, 3.1, 4.2, 5.1.
- [Apple Developer Program – Enrollment](https://developer.apple.com/help/account/membership/program-enrollment/) — Volljährigkeit, Anmeldung, Preise.
- [Kostenlose Developer-Registrierung (Altersgrenzen)](https://developer.apple.com/de/register/) — Deutschland ab 16 Jahren.
- [Xcode SDK/System Requirements](https://developer.apple.com/xcode/system-requirements/) — iOS/watchOS Targets, aktuelle Toolchain.
- [Apple Watch/iPhone-Kompatibilität](https://support.apple.com/de-de/118490) — Series 3 bis watchOS 8.8.1.
- [APNs: Server einrichten](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server).
- [APNs: Gerät registrieren](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).
- [Benachrichtigungsaktionen](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions).
- [Text-/Diktatantwort auf Push](https://developer.apple.com/documentation/usernotifications/untextinputnotificationaction).
- [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity).
- [App Intents](https://developer.apple.com/documentation/appintents).
- [WatchKit-Texteingabe](https://developer.apple.com/documentation/watchkit/wkinterfacecontroller).
- [Mikrofon-Datenschutzstring](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription).
- [Informationen für App Review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review).

> **Quellen- und Realitätscheck:** Apples Richtlinien, SDK-Unterstützung und der Metis-Code ändern sich. Codex muss die aktuelle Fassung **vor** Implementierung und **vor** App-Store-Submission erneut prüfen. Repo-Angaben basieren auf der genannten Commit-Basis, nicht auf der Behauptung, alle APIs vollständig getestet zu haben.
