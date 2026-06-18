# Swell — Calendar Surf Escape Feature Spec

**Date:** 2026-06-18
**Status:** Draft — scoping
**Author:** Patrick (with Hermes)

---

## Purpose

Add a "Surf Escape" feature to the Swell menubar app that lets users instantly create a calendar event with a specified duration, using an LLM to generate a funny, innocuous meeting title. This enables the user to block time on their calendar to go surf without revealing the true purpose.

Examples of generated titles:
- "Underwater Basket Weaving"
- "Building a Snowman"
- "Walking My Tiger"
- "Competitive Cloud Gazing"
- "Teaching My Goldfish Tricks"

---

## Goals

- **One-click calendar block**: User picks a duration (30m, 1h, 2h, custom), hits "Go Surf", event is created.
- **Plausible deniability**: LLM generates a harmless, amusing meeting title each time.
- **Minimal friction**: No multi-step flows, no manual title entry.
- **Local-first**: LLM runs on-device (MLX / llama.cpp) or via lightweight local server; no cloud dependency.
- **Integrate naturally**: Lives in the existing menubar dropdown, alongside "Sample now" / "Quit".

---

## Non-Goals (v1)

- Recurring events
- Multiple calendar support (pick default once in Settings)
- Invitees / attendees
- Location field (could add "Santa Cruz, CA" later)
- Advanced LLM prompt engineering / user-customizable prompts
- Conflict detection / busy-check (EventKit handles double-booking warnings)

---

## User Flow

```
User clicks menubar icon → dropdown opens
       ↓
Sees footer:  [30m] [1h] [2h] [Custom…]  [Go Surf 🌊]
       ↓
Clicks duration button (e.g., "1h")
       ↓
Clicks "Go Surf"
       ↓
App requests Calendar permission (first time only)
       ↓
LLM generates title → "Competitive Cloud Gazing"
       ↓
EventKit creates event: now → now+1h, title="Competitive Cloud Gazing"
       ↓
Toast/confirmation in dropdown: "🌊 Blocked 1h as 'Competitive Cloud Gazing'"
```

---

## Architecture

### New Modules

| Unit | Responsibility | Seam |
|------|----------------|------|
| `CalendarService` (protocol) | `createEvent(duration: TimeInterval, title: String) async throws` | EventKit impl; testable with in-memory mock |
| `EventKitCalendarService` | Wraps `EKEventStore`, requests access, writes to default calendar | `CalendarService` impl |
| `MeetingTitleGenerator` (protocol) | `generateTitle() async -> String` | Swappable: local LLM, static list, remote API |
| `LocalLLMTitleGenerator` | Uses MLX / llama.cpp to generate titles on-device | `MeetingTitleGenerator` impl |
| `StaticTitleGenerator` | Falls back to shuffled static list if LLM unavailable | `MeetingTitleGenerator` impl |

### Data Flow

```
MenuViewModel.userTappedGoSurf(duration:)
       ↓
CalendarService.createEvent(duration:, title: await MeetingTitleGenerator.generateTitle())
       ↓
EventKitCalendarService → EKEventStore.saveEvent()
       ↓
MenuViewModel shows confirmation toast
```

### Permissions

- `NSCalendarsUsageDescription` in Info.plist: "Swell creates calendar events so you can block time to go surf."
- Request access on first "Go Surf" tap (not at launch).

---

## UI Placement

### Menubar Dropdown Footer (replaces current 2-button row)

```
┌────────────────────────────────────────────┐
│ Swell                    🌊  Updated 2m ago │
├────────────────────────────────────────────┤
│ Conditions: 3.2ft @ 12s  |  Tide: 2.1ft ↑  │
├────────────────────────────────────────────┤
│ Cowells          3  🟢 Emptier than usual  │
│ Seacliff         7  🟡 About typical       │
│ …                                            │
├────────────────────────────────────────────┤
│  [30m] [1h] [2h] [Custom…]   [Go Surf 🌊]  │
└────────────────────────────────────────────┘
```

- Duration pills: single selection, highlighted when active.
- "Custom…" opens a small popover with a stepper (15m increments, 15m–4h).
- "Go Surf" disabled until duration selected.
- After success: show inline confirmation for 3s, then revert to duration picker.

### Settings (new gear icon in header or footer)

- Default calendar (EventKit calendar picker)
- Default duration (persist last selection)
- LLM backend: Local (MLX) / Static fallback / Disabled
- Test LLM button (generates a title without creating event)

---

## LLM Integration Options

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **MLX Swift (llama-3.2-1b/3b)** | Fully local, fast on Apple Silicon, no server | Bundle size (~1-2GB), first-run download | **Preferred for v1** |
| **llama.cpp (swift bindings)** | Smaller models (GGUF), flexible | More complex integration, slower token gen | Alternative |
| **Static list only** | Zero deps, instant, reliable | Gets repetitive | **Fallback / MVP** |
| **Local HTTP server (Ollama / LM Studio)** | Model flexibility, shared with other apps | Requires running service, network hop | v2 |

### Prompt Strategy (for local LLM)

```
System: You generate harmless, amusing, fictitious meeting titles for a calendar
        event. The user is actually going surfing. Titles should be 2-5 words,
        wholesome, slightly absurd, and believable as a fake meeting.
        Examples: "Underwater Basket Weaving", "Competitive Cloud Gazing",
        "Teaching My Goldfish Tricks", "Walking My Tiger".
        Output ONLY the title, no quotes, no preamble.

User: Generate a meeting title.
```

- Temperature: 0.8–1.0 for variety
- Max tokens: 16
- Stop sequences: newline, period

---

## Dependencies

- **EventKit** — system framework (already available)
- **MLX Swift** — `https://github.com/ml-explore/mlx-swift` (if using MLX)
- **llama.cpp Swift bindings** — alternative
- Or **static array** for MVP (zero deps)

---

## Testing

| Unit | Approach |
|------|----------|
| `EventKitCalendarService` | Integration test with temporary calendar (requires Calendar access in CI) or mock `CalendarService` |
| `MeetingTitleGenerator` | Test static generator; LLM generator tested manually |
| `MenuViewModel` | Unit test duration selection, go-surf flow with mocked services |

---

## Open Decisions

1. **LLM backend for v1**: Start with static list + MLX as stretch? Or bundle a tiny quantized model (e.g., SmolLM-135M, ~100MB)?
2. **Where to put "Custom" duration UI**: Popover from dropdown vs. Settings pane?
3. **Confirmation UX**: Toast in dropdown vs. system notification?
4. **Bundle size budget**: MLX + 1B model ≈ 1.5GB. Acceptable?
5. **Calendar selection**: Default calendar only, or picker in Settings?

---

## Milestones

| Milestone | Scope |
|-----------|-------|
| **M0: MVP (Static Titles)** | EventKit integration, static title list, duration pills, Go Surf button, permission handling, confirmation toast |
| **M1: Local LLM** | Integrate MLX/llama.cpp, download model on first use, generate titles on-device |
| **M2: Polish** | Settings pane, default calendar picker, persist duration, test LLM button, better confirmation UX |

---

## Estimated Effort

| Task | Estimate |
|------|----------|
| EventKit service + permission flow | 2–3h |
| Duration picker UI + MenuViewModel wiring | 2h |
| Static title generator + confirmation toast | 1h |
| Settings integration (gear icon, calendar picker) | 2h |
| **M0 Total** | **~7–8h** |
| MLX integration + model bundling | 4–6h |
| Prompt tuning + generation latency optimization | 2h |
| **M1 Total** | **~6–8h** |

---

## Risks

- **EventKit permission denial**: Handle gracefully; show inline "Enable in System Settings" link.
- **LLM latency**: First token ~1–2s on MLX; acceptable for this use case. Show spinner on "Go Surf".
- **Bundle size**: If MLX + model too large, fall back to static list or smaller model (SmolLM, Phi-3-mini-4k quantized).
- **App Sandbox**: `MenuBarExtra` apps can be sandboxed. EventKit works in sandbox with usage description. Verify.