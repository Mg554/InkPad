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
- `foregroundStyle(cond ? .a : .b)`: write `Color.a`.
- Notification center (`UNUserNotificationCenter`) crashes apps run inside
  Swift Playgrounds; it works in the installed app.
- `@preconcurrency` on a conformance to an already main-actor protocol
  warns; use it only where the compiler asks.

## Layout

```
InkPad.swiftpm/
  App/        entry point (appearance, Scribble gate install)
  Models/     notes, pages, workspace data (planner, decks, study, Flowmodoro)
  Storage/    LibraryStore, WorkspaceStore, backups (ZIP): the only code that touches files
  Canvas/     PencilKit host, tools, lasso, laser, text boxes, keyboard support
  Rendering/  page backgrounds, PDF, thumbnails, PDF/PPTX/ZIP export
  Audio/      recording and playback synced with ink
  Slides/     reading notes (Vision) and writing slide decks
  AI/         AI providers (Anthropic, OpenAI-compatible, Apple), study prompts
  Views/      SwiftUI screens
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
