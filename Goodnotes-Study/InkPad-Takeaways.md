# Goodnotes 7.1.36 → InkPad: what to borrow

**How this was produced:** static analysis of the installed `/Applications/Goodnotes.app` with the
Craft Anything MCP server (Deep mode, no code executed). Every claim below is backed by an evidence id
in `Goodnotes-Evidence-Report.md` (15 findings, `fnd_1`–`fnd_15`). Nothing was copied from Goodnotes —
only the *ideas* and *architecture* are taken, which is what we want.

---

## 0. What Goodnotes actually is (in one paragraph)

A 539 MB Mac Catalyst build, one universal binary, 45 bundled frameworks, 46 on-device Core ML models,
16 languages, 61 feature-localisation files. The content model is a **versioned schema of typed note
items** (pen strokes, text, images, math, shapes, sticky notes), mutated by **commands**, persisted as
**events**, rendered by a **custom Metal stack** (not UIKit), and organised as **tabs inside folders**.
On top of that sits a metered AI assistant, handwriting beautification, handwritten-math solving, audio
that reveals writing in sync, an education platform, and a template marketplace.

---

## 1. Architecture ideas (the long-lasting value)

### A1. A typed item schema with per-item-type migrations ⭐ biggest structural win

**Goodnotes:** the `Schema` module defines typed items — `PenStrokeNotesItem` (v1 **and** v2),
`TextNotesItem` (v1, v2, `TextFragment`), `ImageNotesItem`, `MathNotesItem`, `FillShapeNotesItem`,
`FillPathNotesItem`, `FillEllipseNotesItem`, `SerializedShape/Line/Sticky`, all behind
`AnyNotesItemDescriptor`. `GoodNotesCore` then has `NotesItemMigration` with **one migrator per item
type** (`TypingNotesItemMigrator`, `TextBoxNotesItemMigrator`), plus `LiveSchemaCompatibility` and a
`DebugSchemaVersionOverride`.

**InkPad today:** `PageElement` + `NoteContent.metadata.elements` in a versioned JSON file. We bump
versions by hand and rely on optional fields.

**Why it matters for us:** our "add an optional field to JSON" approach works at 1.0 but is exactly what
breaks at 3.0. A typed-item layer lets us:
- migrate *one kind of item* without rewriting the whole file;
- version items **independently of the file** (a v2 pen stroke inside an older document);
- reuse item types across contexts (note, whiteboard, slide, mind map) — which is how Goodnotes shares
  one `NotesItem` vocabulary everywhere.

**How to build:** `protocol PageItem { var itemVersion: Int }` + a `ItemMigrator` registry keyed by
`(type, fromVersion, toVersion)`; `PageElement` becomes a sum type over concrete items instead of one
fat enum with optionals. Keep the file's `version` as the *file* format version and add
`item.version` per item. **This is a refactor of `Models/PageElement.swift` + `NoteContent.swift` and it
would pay for itself the first time we add a fifth stroke type.**

### A2. Commands + events instead of direct mutation

**Goodnotes:** `CreateDocumentCommand`, `ImportDocumentCommand`, `ExportDocumentCommand`,
`ExportPagesCommand`, `CreateProblemCommand`, `CreateDRMCommand`; events `DocumentCreated`,
`PageCreated`, `CourseCreated/Updated`, `ProblemCreated/Updated`, `TemplateCreated`, `DRMCreated`,
`DocumentMigrated`. The store observes writes (`NotesStoreWriteObservation`).

**InkPad today:** views call `canvas.shiftContent(...)`, `session.insertPage(...)` directly.

**Why it matters:** every mutation becomes replayable, undoable and sync-able for free, and "undo" stops
being a special case. It is also the only sane way to add real-time collaboration later.

**How to build:** a `NoteCommand` enum + `apply(command)` on `EditorSession`, appending an
`Event` to a per-note log (JSONL next to the note). Start with just `DocumentCreated`, `PageCreated`,
`ItemAdded`, `ItemMoved`, `ItemDeleted`, `DocumentMigrated`.

### A3. A layered notes store (memory → durable) with subscriptions

**Goodnotes:** `InMemoryNotesStore`, `InMemorySyncNotesStore`, `AsyncInMemoryNotesStore`,
`DBProvidedNotesStore`, `CachedRejectedNotesStore`; `ListNotesItemsSubscription(+Handler)`;
`WebVersionedNotesFetcher` + `WebDocumentNotesPreFetcher`.

**InkPad today:** `EditorSession` holds `baseContent`, mutates, autosaves to disk.

**Why it matters:** the UI currently waits on the file. A memory store + subscription means the canvas
never blocks on I/O, and prefetching a note you are about to open becomes trivial.

**How to build:** `NoteStore` protocol with `InMemoryNoteStore` (current session) and
`FileNoteStore` (today's JSON), a `@Published`/AsyncStream of items, and a prefetch when the user
hovers a note in the library.

### A4. Storage: two stores, not one

**Goodnotes:** **RocksDB** (`RocksIndexDatabase`, `LoggingDatabaseWriter`) *and* **GRDB/SQLite**
(`DatabasePool`, `DatabaseQueue`) — a key-value index plus a relational store.

**InkPad today:** JSON files only, plus a Spotlight index.

**Why it matters:** JSON is great for a note and terrible for "all notes, all pages, full-text search,
thumbnails, sync state". We already feel this — Spotlight needed a *rebuild* command.

**How to build:** keep JSON as the **portable, human-readable source of truth** (our differentiator) and
add a **SQLite index** (via GRDB or plain SQLite3) for search, sorting, tags, thumbnails and sync
bookkeeping. Then "Rebuild Spotlight Search" becomes unnecessary because the index is always live.

### A5. A Metal renderer — *know when not to copy this*

**Goodnotes:** `RendererInterface` (Rasterizer, `ImmutableIOData`, `SharedRendererView`,
`Texture/DrawableOutputImage`, RendererAnimator) + `RendererV4` (`JobPlanner`, `AtlasTexture`,
`StrokesCache`, `RendererEngine`, `MetalGPUContext`, plus a `FakeCPUContext` fallback). They run
**New / Legacy / Unified** renderer paths side by side per tool during their own migration.

**InkPad today:** we use **PencilKit** (Apple's renderer) + our own `ElementLayerView`/`ElementRenderer`.

**Assessment:** Goodnotes built their own renderer because they needed variable-width pressure-sensitive
strokes, cross-tool live sync and a minimap that PencilKit cannot do. **We should not rebuild a Metal
ink engine** — PencilKit is excellent and free. But two things are worth stealing:
1. the **New/Legacy/Unified** pattern — run the old and new canvas paths side by side behind a flag
   while we migrate, instead of a big-bang rewrite;
2. the idea of a **renderer abstraction** (`RendererInterface`) so the canvas can swap backends.

### A6. Minimize and preview (a minimap)

**Goodnotes:** `MinimapRenderer` + `MinimapRendererContext` — a live miniature of the whole document.

**InkPad today:** `PageNavigator` (page thumbnails list) but no live spatial minimap.

**Why it matters:** with horizontal scrolling (our new Scrolling Direction) and long notes, a minimap is
the cheapest way to keep orientation. **Small, self-contained, high value.**

---

## 2. Feature ideas, ranked by (value × ease) for InkPad

### ⭐⭐⭐ Tier 1 — do these first

#### F1. Import Goodnotes files  ← the single biggest opportunity
Goodnotes' `.goodnotes` is a **zip package** (our UTI read confirms `LSTypeIsPackage: true`, plus
`.enote`/`.notes` legacy single files). InkPad currently imports **nothing** from the biggest note app
on the planet. Even a *read-only* importer (ink + text + images → our `PageElement`s) would be a
killer feature for anyone switching.
*Known unknown:* whether the ink inside is PencilKit `PKDrawing` data or Goodnotes' own
`PenStrokeNotesItem` encoding — we need one real `.goodnotes` file to settle this (unknown #1).
*Effort:* medium. *Payoff:* very high.

#### F2. Real handwriting **math** recognition for the calculator
Goodnotes ships **CoMER** (encoder + decoders at 40/80/160) — a transformer trained for
mathematical-expression recognition — and then *does algebra on it*: solve, simplify, factorise, expand,
multiply-with-conjugate, partial-fraction decomposition, canonical form, mixed/improper fraction,
sum-of-logs-to-product, expand log, expand/linearise exponentials, arc-cos↔arc-sin↔arc-tan conversions,
tan(x)→sin(2x), half-tangent, trig expansion. Results can be copied as **LaTeX**, as the **original
handwriting**, or as an image; the user can report "graph does not match input".
Our `Calculator/MathExpression.swift` currently reads handwriting via **Vision text recognition**, which
is exactly the wrong tool for `∫`, `√`, fractions and superscripts.
*Our advantage:* we already have a clean arithmetic engine and an editable printed expression.
*Next step:* Apple's **Vision has `VNRecognizeMathExpressionRequest`** (iOS 18+) — a system math
recogniser we can adopt before ever considering a Core ML model. Then add a symbolic layer for
simplify/factorise.
*Effort:* medium (Vision request) → high (symbolic). *Payoff:* very high — it turns our calculator from
a novelty into the best math feature in the class.

#### F3. Audio that reveals the writing in sync
Goodnotes' audio notes have three playback behaviours: **spotlight**, **real-time reveal** and
**static** — the recording plays while the handwriting appears as it was written.
**InkPad already has both halves:** `Canvas/InkReplay.swift` + `Views/RecordingTimelineView.swift` +
`Audio/AudioController.swift`. This is a case where **we are already ahead or level** — we should
double-check our mode names/behaviour match Goodnotes' three, because that vocabulary is already proven
in the market. *Effort:* low (verify + rename). *Payoff:* medium-high.

#### F4. "Ask" scoped to a selection, with tone control, image and diagram generation
Goodnotes' **Ask Goodnotes** sidebar answers about the current page **or a page range**, and can:
change tone, **create an image**, **create a diagram/flowchart** (with light/dark variants), run in
**agent math mode** or **lasso mode**, and it is **credit-metered**. It also tags AI content and shows a
data-protection disclaimer.
**InkPad today:** `AIChatView` (general chat) + `AskPageView` (ask this page). We have the plumbing.
*Missing:* selection-scoped ask (our lasso already knows the selection!), change-tone, image/diagram
generation, and a quota/credit model.
*Effort:* low–medium. *Payoff:* high.

### ⭐⭐ Tier 2 — strong value

#### F5. AI Typing rewrite menu
Goodnotes lets you take selected text and: make longer / make shorter, fix grammar and spelling,
paraphrase, change tone (casual / confident / friendly / professional), convert to bullet points — with
its own quota.
**InkPad:** no equivalent. Our `AI/AIClient` can do all of it already; it is a menu on top of the text
box. *Effort:* low. *Payoff:* high — this is the most-used AI pattern in consumer productivity apps.

#### F6. Spellcheck, Word Complete, Scribble-to-Erase, Circle-to-Lasso
Goodnotes ships a **Writing Aids** layer: spellcheck with ignore-all/add-to-dictionary, **Word
Complete** (predicts the rest of a word you are tip-of-the-tongue about), **Scribble to Erase**, and
**Circle to Lasso** — each with its own onboarding.
**InkPad:** none of this. Our `HandwritingRefiner` and `ShapeRecognizer` are close cousins of the same
idea (post-hoc interpretation of ink).
*Effort:* Word Complete = low (a prefix dictionary + inline completion); spellcheck = low
(`UITextChecker`); Scribble-to-Erase = medium (stroke-shape erase, we already have `LassoSelection`).
*Payoff:* high — these are daily-use features.

#### F7. Floating Layers
Goodnotes' canvas has a **Floating Layers** panel: named layers, each with its own notes, a
collapsed/expanded control, selection banners, and a layer-per-row state.
**InkPad:** `Views/FloatingPlacement.swift` floats *toolbars*; it does **not** float *content layers*.
*Effort:* medium-high (needs a layer model in the item schema — do it *after* A1).
*Payoff:* high for study use (layer 1 = your notes, layer 2 = the teacher's slides, layer 3 = answers).

#### F8. Tab-based notebooks
Goodnotes 6/7 replaced "pages in a notebook" with **tabs in a notebook** (UTI `com.goodnotes.tab`,
`GN6AppServices.TabManager`, `DraggedTab`, a root tab bar). We just shipped **horizontal scrolling** —
tabs are the same idea organised differently, and the two compose.
*Effort:* medium. *Payoff:* medium-high.

#### F9. The eraser, properly
Goodnotes' eraser has five modes — **object, pixel, precision, segment, stroke** — plus filters
(highlighter only, tape only) and auto-deselect. Pixel mode erases to the pixel (smudge), object mode
removes whole items, precision mode erases a thin slice, segment mode erases a whole segment of a
stroke.
**InkPad:** PencilKit's eraser + our own.
*Effort:* low–medium. *Payoff:* medium.

#### F10. Templates, marketplace and creator attribution
Goodnotes has a **Content Store / Template Library** with groups, 20+ colour presets, import/export,
a **marketplace**, and **creator attribution cards** ("created by", "about the creator").
**InkPad:** `TemplateGallery` + `Plugins`. We could add creator attribution and groups.
*Effort:* low–medium (needs a backend for a real marketplace; can ship local-only first).
*Payoff:* medium.

### ⭐ Tier 3 — worth knowing, later

| Idea | Goodnotes evidence | InkPad note |
|---|---|---|
| **Whiteboard** canvas type (blank/dot-grid/square-grid, convertible to a notebook, quota-limited) | `Canvas.strings`, `GN6LibraryUI` | Cheap to add: a `PaperSize` + background style. Real whiteboard is a bigger job. |
| **Nexus** block editor (H1–H3, paragraph, bulleted/numbered/nested lists, check lists, code, quote) | `Nexus.strings`, `NexusEnhanceMeetingNotesEvent` | This is Goodnotes' *text-first* mode. We have `MarkdownNoteView` — **we may already have the equivalent**; worth comparing before building. |
| **Education platform**: Classroom/LMS ("Ask Classroom"), assignments, problems, courses, exam prep with AI dashboard, mock exams, study sets | `Classroom.strings` (171 KB!), `ExamPrep.strings`, `Learn.strings`, `Schema.ClassroomAssignment`, `ProblemCreated/Updated` | We have `StudyView` + flashcards + quizzes. The **assignment/problem** model (teacher marks work, student submits) is a whole new product line — huge, but not a v1 item. |
| **Real-time collaboration** (WebRTC + PubNub + `CommonRTCCursor` live cursors + comments) | Mach-O load commands, `CommentKit`, `Schema.CommentThread` | Requires a backend. Our A2 (commands/events) is the prerequisite. |
| **Migration**: Goodnotes 4 and iCloud notebook migration, resumable, per-item error reporting | `Migration.strings` | Pairs with F1. |
| **Handwriting beautification with a review loop** (see original / accept / rewrite + structured feedback: wrong content, layout issue, mismatched style, wrong colour, not readable, too slow) | `HandwritingBeautification.strings` | We have `Canvas/HandwritingRefiner.swift`. Adding the **review loop + feedback categories** is cheap and makes the feature trustworthy. |
| **Tape** (mask areas with solid colour, gradients or uploaded patterns) | `Tape.strings` | Low effort, fun, moderate value. We have sticky notes already. |
| **Diagrams / Mermaid** | `SwiftMermaid` bundle, `MathJaxSVGRenderer`, `MathLaTeXPreviewRenderer` | We have mind maps; Mermaid-style text→diagram would extend them. |
| **Enterprise/commercial**: license keys, MSAL, Intune, organization & team tiers | `DRM.strings`, `GNDRM`, `MSALSettings`, `IntuneWrapper`, `Organizations` | Only if we go B2B. |
| **Audio detail**: playback speed, noise reduction, export, per-recording transcription, notes visibility modes | `GNAudioRecordings.strings` | We have record/play/transcribe. Speed + noise reduction are cheap wins. |

---

## 3. Things Goodnotes does that we should **not** copy

1. **Their size.** 539 MB binary, 45 frameworks, RocksDB + GRDB + CloudKit + PubNub + Braze + Datadog +
   Amplitude + AppsFlyer + Bugsnag + Facebook + Google sign-in + AWS Cognito + VPP partner licensing.
   That is a company with a hundred people. InkPad's strength is that it is one honest, local-first app
   with no account required — **keep it**.
2. **Their analytics/ad-tech surface** (`NSPrivacyTrackingDomains` lists ten AppsFlyer domains).
   InkPad should stay tracker-free. If we ever add analytics, make it opt-in and local.
3. **Credits/quotas as a UX.** We can borrow the *idea* of showing AI cost honestly, but we should not
   meter a feature users already paid for.
4. **GN5 and GN6 coexisting.** Goodnotes ships the old Goodnotes-5 UI (`GN5iOSUI`, `GN5App`) *and* the
   new Goodnotes-6 UI (`GN6iOSUI`, `GN6App`) in the same binary — 11+13 classes of duplicated UI. That
   is the cost of a long migration, and it is an argument for our **versioned-JSON + optionals**
   approach being simpler for a small app. (We can steal their *migration tooling*, not their
   duplication.)

---

## 4. Recommended order of work

| # | Item | Why now | Effort |
|---|---|---|---|
| 1 | **F4** Ask: selection-scoped + tone + image/diagram | We already have the client; fastest visible win | low |
| 2 | **F5** AI Typing rewrite menu | Same client, one menu | low |
| 3 | **F2** Math recognition via `VNRecognizeMathExpressionRequest` | Our calculator is our differentiator; make it correct | medium |
| 4 | **F3** Verify/rename our ink-replay modes (spotlight/reveal/static) | We may already have this | low |
| 5 | **A6** Minimap | Cheap, high orientation value | low–medium |
| 6 | **F6** Word Complete + spellcheck | Daily-use, low effort | low–medium |
| 7 | **A1 + A2** Typed item schema + command/event log | The structural enabler for layers, collaboration, sync and history | high |
| 8 | **F1** Goodnotes import | Biggest market win, needs a sample file first | medium |
| 9 | **F7** Floating Layers | Needs A1 first | medium |
| 10 | **F8** Tabs | Composes with horizontal scrolling | medium |

---

## 5. Open questions (recorded in the investigation as unknowns)

1. **HIGH** — Is the ink inside a `.goodnotes` package PencilKit `PKDrawing`, or Goodnotes' own
   `PenStrokeNotesItem` encoding? *Decides whether F1 can import ink faithfully or only images/PDF.*
   *Probe:* open one real `.goodnotes` file with `core_target_open` and inspect its entries.
2. **MEDIUM** — How much of the AI is on-device vs. metered server-side? Goodnotes shows credits and
   quota errors, so "Ask Goodnotes" is server-side; the ML zoo is local.
3. **MEDIUM** — What exactly is **Nexus**? A new notebook format, a separate document type, or the
   successor to the classic page canvas?
4. **LOW** — What is shared between Floating Layers?

**Next step for #1:** we need one real `.goodnotes` file. If you have one in your Goodnotes library
(e.g. `~/Library/Containers/com.goodnotesapp.x/…` or an iCloud Drive copy), point me at it and I will
open it with Craft Anything and finish the answer — that turns F1 from "probably" to "specified".

---

*Evidence ledger: `Goodnotes-Evidence-Report.md` (15 findings with evidence ids).*
*Produced with Craft Anything 0.6.1 in Deep mode; nothing in Goodnotes was executed.*
