<div align="center">

# ☾ Starlight Terminal

**A starlit TUI console for sky observations — that carries a real coding agent inside it.**

[![Download APK](https://img.shields.io/badge/Download-APK-7CFFC4?style=for-the-badge&logo=android&logoColor=020705)](https://github.com/Starlightmii/starlight-terminal/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.9-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#)
[![License](https://img.shields.io/badge/license-MIT-FFD166?style=for-the-badge)](#license)

</div>

---

## What is this?

Starlight Terminal looks like a CRT phosphor observatory console. Boot it and you
get a scanline-lit terminal, four phosphor palettes, a star map, and a scrollback
buffer that remembers.

Underneath the chrome it is a **full pi coding agent runtime**: providers, a
direct model client, a virtual filesystem, craftable agents with a scheduler,
persistent sessions and a memory map — all running on-device, no broker in the
middle.

It started as a sky-observation console. It kept growing until it was an agent
platform that happens to be about the sky.

---

## ✦ Screens

| Screen | What it does |
|---|---|
| **BOOT** | Power-on sequence, palette selection, phosphor self-test |
| **TERMINAL** | The console. Scrollback, `*emphasis*` markup, phosphor bloom |
| **PI** | The agent core — model picker, session, `/command` routing |
| **CONSOLE** | Shell console for pi subcommands |
| **AGENTS** | Craftable agents: AUTO / interval / standing task / RUN NOW |
| **SKY MAP** | Star catalogue, MAP/LIST toggle, tappable rows |
| **SESSIONS** | Save, resume, fork, clone, compact, export as JSONL |
| **CATALOGUE** | 88 named stars with real identifiers |
| **KEYS** | Provider key vault — reveal, test, `USE FOR PI`, refresh models |
| **LOG** | App log inspector |
| **EFFECTS** | FX painters — circuit, bloom, glyphrain |

---

## ✦ The pi agent core

The app tracks the genuine **`@earendil-works/pi-coding-agent`** package. On
Flutter web there is no subprocess, so it talks to the real `pi` binary through a
local bridge and proxies it same-origin:

```bash
node /home/user/pi-bridge/server.mjs      # pi bridge, port 5077
python3 serve.py 5060                     # static app + /pi/* proxy
```

Keeping the proxy same-origin means no CORS and no hardcoded host.

### Commands

Every command is routed through `pi_session`:

```
/help  /status  /version  /model  /models  /use  /keys  /commands
/install  /net  /thinking  /scoped-models  /login  /logout  /settings
/new  /resume  /session  /name  /tree  /fork  /clone  /compact  /context
/import  /copy  /export  /share  /bug  /skills  /skill  /reload  /hotkeys
/changelog  /update  /clear  /quit  /debug
```

### Models & providers

Models are provider-driven, not hardcoded. Every entry carries the vault
provider that routes it — a model is only useful if you know **which key pays
for it**:

```dart
PiModelEntry(id, vendor, context, reasoning,
  providerId: 'openrouter',   // which credential pays
  free: true,
);
```

---

## ✦ Screens in detail

**Four phosphor palettes.** Each is a full colour role set — background, panel,
hairline, dim, mid, bright, and ok/warn/err — so the whole app re-themes at once:

| Palette | Character |
|---|---|
| `PHOSPHOR` | P1 green — the classic observatory tube |
| `AMBER` | Warm amber, low-light cockpit |
| `ICE` | Cold blue-white |
| `NEBULA` | Deep violet |

**Inline styling DSL.** The terminal renders `*emphasis*` as a brightened run.
An unmatched trailing `*` is kept literally rather than swallowed, so you can
type asterisks safely.

**Craftable agents.** Each agent has its own engine (`local` uses the app's
tool catalogue; `pi` reaches the real CLI through the bridge), its own
transcript with `sys` / `you` / `agt` / `tool` roles, and a scheduler bar for
autonomous runs. One ticker drives the whole fleet rather than one per agent.

**Key vault.** Keys live in `shared_preferences`, never in source. The KEYS
screen can reveal, test, assign `USE FOR PI`, and refresh the model catalogue.

---

## ✦ Architecture

```
lib/
├── main.dart                    entry — installs the HTTP bridge, runs the app
├── core/
│   ├── pi_core.dart             pi package core: install lifecycle, model catalog
│   ├── pi_commands.dart         the /command table
│   ├── providers.dart           vault provider routing
│   ├── model_client.dart        direct model client
│   ├── agent_runtime.dart       agent turns, engines, transcripts
│   ├── agent_scheduler.dart     fleet ticker
│   ├── vfs.dart                 in-app virtual filesystem
│   ├── session_store.dart       persistent sessions
│   ├── users.dart               multi-user accounts
│   ├── memory.dart              memory map
│   ├── catalogue.dart           88-star catalogue
│   ├── console_engine.dart      terminal lines, tones, markup
│   ├── effects.dart             FX painters (circuit / bloom / glyphrain)
│   └── palette.dart             the four phosphor palettes
├── state/                       pi_session, studio, terminal controllers
└── ui/                          shell, chrome, and eleven screens
```

State is `provider` + `ChangeNotifier`. Three controllers drive everything:
`TerminalController` (the console), `StudioController` (agents and catalogue),
`PiSession` (the core).

---

## ✦ Download

**Android APK** — universal, arm64-v8a / armeabi-v7a / x86_64:

[![Get the APK](https://img.shields.io/badge/GET%20APK-52.7%20MB-7CFFC4?style=for-the-badge&logo=android&logoColor=020705)](https://github.com/Starlightmii/starlight-terminal/releases/latest)

> **Package** `com.starlightterminal.stars` · **version** `1.0.0` · **minSdk** 16
> Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `DUMP`

Grab it from the [Releases page](https://github.com/Starlightmii/starlight-terminal/releases/latest).

---

## ✦ Build it yourself

```bash
flutter pub get
flutter run                      # dev
flutter build apk --release      # Android
flutter run -d chrome            # web (needs the bridge for /pi/*)
```

Run the tests:

```bash
flutter test
```

---

<div align="center">

**Starlight Memories** · Jaipur, Rajasthan

*Built with Flutter and an unreasonable number of phosphor colours.*

</div>
