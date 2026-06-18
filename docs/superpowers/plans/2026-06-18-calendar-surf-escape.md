# Swell — Calendar Surf Escape Implementation Plan

**Date:** 2026-06-18
**Spec:** `docs/superpowers/specs/2026-06-18-calendar-surf-escape.md`
**Branch:** `feature/calendar-surf-escape`

---

## Task Breakdown

### Phase 0: Foundation (EventKit + Static Titles)

#### T0: Add EventKit dependency & Info.plist usage description
- [ ] Add `NSCalendarsUsageDescription` to `Sources/Info.plist`
- [ ] Verify sandbox compatibility (MenuBarExtra + EventKit)

#### T1: Create `CalendarService` protocol & `EventKitCalendarService` impl
- **File:** `Sources/Calendar/CalendarService.swift` (new)
- **Protocol:**
  ```swift
  protocol CalendarService {
      func requestAccess() async -> Bool
      func createEvent(duration: TimeInterval, title: String) async throws
      var isAuthorized: Bool { get }
  }
  ```
- **Impl:** `EventKitCalendarService` wrapping `EKEventStore`
  - Use default calendar (or allow selection later)
  - Event: start = now, end = now + duration, title = generated title
  - No alarms, no attendees, no location (v1)

#### T2: Create `MeetingTitleGenerator` protocol & `StaticTitleGenerator`
- **File:** `Sources/Calendar/MeetingTitleGenerator.swift` (new)
- **Protocol:**
  ```swift
  protocol MeetingTitleGenerator {
      func generateTitle() async -> String
  }
  ```
- **Impl:** `StaticTitleGenerator` with shuffled array of ~30 titles
  - Thread-safe, no external deps

#### T3: Wire into `MenuViewModel` — duration selection + Go Surf action
- **File:** `Sources/UI/MenuViewModel.swift` (modify)
- Add `@Published var selectedDuration: TimeInterval?`
- Add `@Published var surfEscapeStatus: SurfEscapeStatus = .idle`
- Add `func goSurf()` → calls services, updates status
- Inject `CalendarService` and `MeetingTitleGenerator` via init

#### T4: Update `MenuContentView` — duration pills + Go Surf button + status
- **File:** `Sources/UI/MenuContentView.swift` (modify)
- Footer replacement:
  - Duration pills: 30m, 1h, 2h, Custom (popover)
  - Go Surf button (disabled until duration selected)
  - Status area: spinner / success message / error
- Keep "Sample now" and "Quit" buttons

#### T5: Add "Custom duration" popover
- **File:** `Sources/UI/CustomDurationPopover.swift` (new)
- Stepper: 15m increments, 15m–4h range
- Dismiss on selection

#### T6: Update `SwellApp` — instantiate services, pass to VM
- **File:** `Sources/SwellApp.swift` (modify)
- Create `EventKitCalendarService()`, `StaticTitleGenerator()`
- Pass to `MenuViewModel` init

#### T7: Unit tests
- **File:** `Tests/CalendarServiceTests.swift` (new)
  - Test `StaticTitleGenerator` returns titles from list
  - Test `EventKitCalendarService` with mock (or skip if no Calendar access in CI)
- **File:** `Tests/MenuViewModelCalendarTests.swift` (new)
  - Test duration selection flow
  - Test goSurf calls services with correct params

---

### Phase 1: Local LLM Integration (MLX)

#### T8: Add MLX Swift dependency
- **Option A:** SwiftPM package `https://github.com/ml-explore/mlx-swift`
- **Option B:** Bundle pre-converted model + minimal runtime
- Decision: Start with SwiftPM for flexibility

#### T9: Create `MLXTitleGenerator` implementing `MeetingTitleGenerator`
- **File:** `Sources/Calendar/MLXTitleGenerator.swift` (new)
- Download model on first use (e.g., `mlx-community/SmolLM-135M-Instruct-4bit` ~100MB or `mlx-community/Llama-3.2-1B-Instruct-4bit` ~1GB)
- Implement prompt template, generation config (temp=0.9, max_tokens=16)
- Handle loading state, errors → fallback to static

#### T10: Add LLM backend selection to Settings
- **File:** `Sources/UI/SettingsView.swift` (new)
- **File:** `Sources/Settings/SettingsStore.swift` (new) — UserDefaults wrapper
- Options: Static / MLX (auto-download) / Disabled
- Persist selection

#### T11: Wire `MLXTitleGenerator` into app based on setting
- Factory in `SwellApp` or `MenuViewModel` init

---

### Phase 2: Polish & Settings

#### T12: Settings UI in menubar dropdown
- Gear icon in header → opens Settings popover/sheet
- Calendar picker (EventKit calendar list)
- Default duration persistence
- LLM backend selector
- "Test LLM" button (generates title without creating event)

#### T13: Improve confirmation UX
- Inline toast with "🌊 Blocked 1h as 'Competitive Cloud Gazing'"
- Auto-dismiss after 3s
- Error handling: permission denied → inline "Open System Settings" button

#### T14: Persist last-used duration
- `SettingsStore.lastSurfDuration` → pre-select on dropdown open

#### T15: Integration test & manual QA
- Full flow: click menubar → select 1h → Go Surf → verify event in Calendar.app
- Permission flow: deny → re-enable in Settings → retry
- LLM fallback: disconnect network / corrupt model → verify static titles used

---

## File Map (New / Modified)

```
Sources/
├── Calendar/
│   ├── CalendarService.swift           ← NEW (protocol + EventKit impl)
│   ├── MeetingTitleGenerator.swift     ← NEW (protocol + Static impl)
│   ├── MLXTitleGenerator.swift         ← NEW (Phase 1)
│   └── CalendarError.swift             ← NEW (error types)
├── Settings/
│   ├── SettingsStore.swift             ← NEW (Phase 2)
│   └── SettingsView.swift              ← NEW (Phase 2)
├── UI/
│   ├── MenuViewModel.swift             ← MODIFY (add Calendar/Title deps)
│   ├── MenuContentView.swift           ← MODIFY (new footer)
│   ├── CustomDurationPopover.swift     ← NEW
│   └── SurfEscapeToast.swift           ← NEW
└── SwellApp.swift                      ← MODIFY (wire services)

Tests/
├── CalendarServiceTests.swift          ← NEW
├── MenuViewModelCalendarTests.swift    ← NEW
└── MLXTitleGeneratorTests.swift        ← NEW (Phase 1)
```

---

## Dependencies to Add (project.yml)

```yaml
packages:
  MLX:
    url: https://github.com/ml-explore/mlx-swift.git
    from: "0.20.0"   # check latest
  # OR for llama.cpp:
  # LlamaCpp:
  #   url: https://github.com/llama-cpp/llama.cpp.git
  #   from: "b..."
```

---

## Verification Commands

```bash
# After each Swift change:
xcodebuild -project Swell.xcodeproj -scheme Swell -destination 'platform=macOS' build

# Run tests:
xcodebuild test -project Swell.xcodeproj -scheme Swell -destination 'platform=macOS'

# Manual QA:
# 1. Build & run
# 2. Click menubar → select duration → Go Surf
# 3. Open Calendar.app → verify event exists with funny title
# 4. Test permission denial / re-grant flow
```

---

## Rollback Plan

If EventKit causes sandbox issues or bundle size problems with MLX:
- Feature flag: `SettingsStore.isSurfEscapeEnabled` (default false)
- Can ship M0 behind flag, enable for beta testers first
- Static titles only = zero new deps, minimal binary impact