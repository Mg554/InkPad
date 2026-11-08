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
- Notification center (`UNUserNotificationCenter`) crashes apps run inside
  Swift Playgrounds; it works in the installed app.
- `@preconcurrency` on a conformance to an already main-actor protocol
  warns; use it only where the compiler asks.

## Layout

```
InkPad.swiftpm/
  App/        entry point (appearance, theme, Scribble gate, automatic backups)
  Command/    Command Anywhere (⌘K): palette, sentence parser, voice, AI fallback
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

- Keyboard after Apple Pencil taps: iPadOS (Scribble) hides it; finger taps
  show it. Check in the Xcode-installed app whether it behaves the same as
  in Swift Playgrounds.
- Bring back Flowmodoro's break-end notification for the installed app
  (it was removed because it crashes inside Playgrounds).
- Library backup/restore, Recently Deleted, page reorder, the AI Firewall
  and Write → Think → Build (lasso › Think, Views/ThinkView.swift) are
  done; test them on the iPad. Every path that sends note text to AI must
  go through `NoteTexts.sources` or check `LibraryStore.isHiddenFromAI`
  (the AI Firewall).
- Colors: use `Color.inkAccent` (the theme's accent), not
  `Color.accentColor`, and `.themedBackground()` on new screens (or
  `.screenBackdrop(_:)` for a screen with its own background). Shared
  style pieces live in Views/Theme/ScreenStyle.swift (backdrops, glow,
  `StoredLook`). Saved settings structs decode with
  `container.value(_:or:)` so adding a field never resets them.
