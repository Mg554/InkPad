# InkPad — notes for Claude

A free, private Notability-style note app for iPad (SwiftUI + PencilKit),
kept as a **Swift Playgrounds app package**: `InkPad.swiftpm`. See README.md
for features and ROADMAP.md for what's next.

## Working with the owner

- Explain plans and actions **in Arabic**; code, comments and commit
  messages stay **in English**.
- Work on `main` and push straight to it (no pull requests).
- Commit as the owner: `git -c user.name="mg554" -c user.email="mohammadmg554@gmail.com" commit`,
  Conventional Commit messages (`feat:`, `fix:` ...).
- The owner tests on an iPad with Apple Pencil and sends screenshots or
  videos; check videos frame by frame (ffmpeg) before changing UI.
- Stay on free tools: no paid Apple Developer Program. The app runs from
  Swift Playgrounds, or is installed from Xcode with a free Personal Team
  (re-run every 7 days).

## Keep it a `.swiftpm` package

- Never convert it to an `.xcodeproj`: it must still open in Swift
  Playgrounds on the iPad. Xcode opens `InkPad.swiftpm` directly.
- App settings (name, bundle id, icon, orientations, microphone permission)
  live in `InkPad.swiftpm/Package.swift`. Xcode may add a `teamIdentifier`
  there when signing; that is fine to commit.
- Swift 5 language mode, iOS 17 target, built with a recent SDK (iOS 18+,
  so `View` is `@MainActor`).

## Building and checking

On a Mac with Xcode, from `InkPad.swiftpm/`:

```bash
xcodebuild -list                                   # find the scheme (InkPad)
xcodebuild -scheme InkPad \
  -destination 'generic/platform=iOS Simulator' build
```

Build after every change and fix all errors and warnings before pushing.
To look at the UI, boot an iPad simulator, run the app, and take
`xcrun simctl io booted screenshot shot.png`. Pencil pressure and feel can
only be judged on the real iPad.

Without a Mac (cloud sessions) the code cannot be compiled, so review
carefully for Swift pitfalls that have bitten before:

- Methods named like `UIResponder`/`NSObject` ones (`copy()`, `cut()`,
  `delete()`), and a property and method sharing a base name.
- `first { }` trailing closures followed by `??`; prefer `first(where:)`.
- Long `+` chains of string literals ("unable to type-check"); join arrays.
- Swift Playgrounds type-checks more slowly than Xcode: an expression Xcode
  accepts can fail there with "unable to type-check this expression in
  reasonable time". Keep expressions short with explicit types (no long
  `|`/`<<`/`+` chains, String + Substring mixes, tuple compares in
  `sorted`, `??` inside arithmetic), and split long SwiftUI modifier
  chains into separate computed properties. Check with
  `OTHER_SWIFT_FLAGS="-Xfrontend -warn-long-expression-type-checking=100"`.
- Never call bare `cos`, `sin`, `sqrt`, `hypot`, `pow`, `log`, `atan`,
  `floor` or `ceil`: on the iPad, Swift Playgrounds reports "ambiguous use
  of 'cos'" when a call could be the Double or the CGFloat version (Xcode
  and Playgrounds on the Mac accept it). Use `Math.cosine`, `Math.sine`,
  `Math.root`, `Math.distance`, `Math.power`... (Models/MathHelpers.swift),
  which take Double, and convert with `CGFloat(...)`.
- This Mac has 16 GB: run only one of Simulator, Swift Playground or
  xcodebuild at a time, and quit it when done.
- `foregroundStyle(cond ? .a : .b)`: write `Color.a`.
- Swift Playgrounds lacks some SDK overlay helpers Xcode finds (e.g.
  `UnsafeMutableAudioBufferListPointer`); its build error shows as a red
  X on the iPad with no detail. Open the package in Swift Playground on
  the Mac to see the message.
- Notification center (`UNUserNotificationCenter`) crashes apps run inside
  Swift Playgrounds; it works in the installed app.
- `@preconcurrency` on a conformance to an already main-actor protocol
  warns; use it only where the compiler asks.

## Subagent workflow (only when the owner says to use it)

Agents live in `.claude/agents/`. They share the weekly limit; the saving is
that cheaper models do the bulky work. Don't use them for small changes (each
starts cold), and keep the one-heavy-tool rule: builds and the simulator run
one at a time.

1. Main session (Opus): interview the owner, design, and write a precise plan
   (files, types, functions, where it hooks in). `code-scout` (Haiku) can find
   the code first.
2. `swift-coder` (Sonnet) implements the plan; independent parts in different
   files may go to two coders at once.
3. `builder` (Haiku) builds simulator + device and lists problems; `fixer`
   (Sonnet) fixes them until clean.
4. Main session reviews the changed parts.
5. `sim-tester` (Sonnet) checks the scenario with few screenshots, then shuts
   the simulator down.
6. `docs-writer` (Haiku) updates the docs and drafts the commit message; the
   main session commits and pushes through GitHub Desktop.

## Layout

```
InkPad.swiftpm/
  App/        entry point (appearance, theme, Scribble gate, automatic backups)
  Command/    Command Anywhere (⌘K): palette, sentence parser, voice, AI fallback
  Living/     Living Notes: on-device concept index, bubble, side panel, concept cards
  PDFTools/   PDF Tools hub, book panel (outline, bookmarks, progress), chapter mind maps and concept graphs
  Models/     notes, pages, workspace data (planner, decks, study, Flowmodoro)
  Storage/    LibraryStore, WorkspaceStore, backups (ZIP): the only code that touches files
  Canvas/     PencilKit host, tools, lasso, laser, text boxes, keyboard support
  Rendering/  page backgrounds, PDF, thumbnails, PDF/PPTX/ZIP export
  Audio/      recording and playback synced with ink
  Slides/     reading notes (Vision) and writing slide decks
  AI/         AI providers (Anthropic, OpenAI-compatible, Apple), study prompts
  Reminders/  Apple Reminders through EventKit
  Views/      SwiftUI screens (Views/Theme: themes and the Theme Mixer)
```

## Open threads

- Keyboard: the owner sees no on-screen keyboard anywhere, even with
  finger taps, and uses a third-party stylus (not Apple Pencil). Likely a
  Bluetooth device iPadOS treats as a hardware keyboard. KeyboardWatcher
  now explains it once (with the device name from GCKeyboard) when typing
  starts without a keyboard; confirm on the iPad what it reports.
- Performance: Swift Playgrounds runs unoptimized builds; keep heavy work
  off the main thread (thumbnails load async and downsampled, note texts
  load in the background, scenery draws asynchronously at 20 fps).
- Bring back Flowmodoro's break-end notification for the installed app
  (it was removed because it crashes inside Playgrounds).
- Library backup/restore, Recently Deleted, page reorder, the AI Firewall
  and Write → Think → Build (lasso › Think, Views/ThinkView.swift) are
  done; test them on the iPad. Every path that sends note text to AI must
  go through `NoteTexts.sources` or check `LibraryStore.isHiddenFromAI`
  (the AI Firewall).
- Language (App/AppLanguage.swift, App/Arabic/): Arabic comes from
  `english => arabic` tables, looked up through a `Bundle.main` hook, so
  every `Text("literal")`/`Label`/`Button` literal is translated; add the
  Arabic line for each new UI string (`{}` for interpolated values). A
  label held in a `String` must go through `tr(...)`; a message built in
  code with values ("12 pages added") through `trMessage(...)`. Never
  translate note titles or anything the owner wrote. The note editor's
  canvas stays left to right.
- Colors: use `Color.inkAccent` (the theme's accent), not
  `Color.accentColor`, and `.themedBackground()` on new screens (or
  `.screenBackdrop(_:)` for a screen with its own background). Shared
  style pieces live in Views/Theme/ScreenStyle.swift (backdrops, glow,
  `StoredLook`). Saved settings structs decode with
  `container.value(_:or:)` so adding a field never resets them.
