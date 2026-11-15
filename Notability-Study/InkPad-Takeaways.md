# InkPad Takeaways from Notability 16.13.5

Companion to `Notability-Report.md` (Craft Anything study, evidence ids there).
Each idea is ranked by (value to InkPad users ÷ effort in a Swift Playgrounds app).
S = small, M = medium, L = large effort.

## Adopt — high value, feasible

| # | Idea | What Notability does (evidence) | Effort | How InkPad would do it |
|---|------|--------------------------------|--------|------------------------|
| 1 | **Shape recognition: hold-to-perfect-shape** | `ShapeClassifier.mlmodelc`: "Single-stroke shape classifier over 64 resampled points", CNN (4×conv, maxPool, softmax, Float16) → classLabel + probs; targets triangle, diamond, ellipse, rectangle, star (fnd_6) | M | Detect "hold at stroke end" after a single stroke; resample to 64 points, classify (ship a CreateML/geometric classifier, no ML needed for v1 — closed-form tests for circle/line/rect/triangle are enough), snap stroke geometry in place with an undo step |
| 2 | **Audio recording linked to ink** | Record while writing; `Recording`/`RecordingSegment`/`AudioLinked`; playback with speed control; trim/split/merge; export ZIP (PDF + recording); Widget "Start recording" (fnd_7) | L | `AVAudioRecorder` while strokes are drawn — save each stroke with a timestamp from recording start; playback bar under the page replays ink synced to audio (show strokes whose time ≤ playhead). V1: one recording per page, play + speed only |
| 3 | **Paper templates as a PDF pack** | 36 templates × 5 sizes × 3 colors × 2 orientations, pre-rendered PDFs + `metadata.json` + thumbnails; `Paper`/`PaperFlair`/`SetPaper` (fnd_11) | S | InkPad already has page backgrounds — adopt the same architecture: template folders (college rule, Cornell, grid, music staves, mind map…) rendered to PDF with a metadata.json (name, size, dark variant). Cornell + planners are the most "study" ones InkPad lacks |
| 4 | **Per-note search index across ink + images (+ audio later)** | `SearchIndex_HandwritingSearchIndex`, `SearchIndex_ImageRecognizedText`, `SearchIndex_PDFSearchIndex`, `SearchIndex_RecordingTranscription`, character rects for highlighting (fnd_4) | M | InkPad has OCR already — persist per-page OCR results (like `HandwritingDataPerPage`) at save time instead of re-recognizing at search time; add image-text (Vision on photos) next; audio transcription last (Speech framework) |
| 5 | **Password-locked folders** | `FoldersPassword.*`: synced password + hint, unlock prompts on open/import/delete/export (fnd_12) | M | CryptoKit: encrypt note payloads with a key derived (PBKDF2) from the folder password; hide note previews/Spotlight metadata for locked notes |
| 6 | **Threading comments anchored to ink** | `CreateComment`/`CommentAnchor`/`ReplyAnchor`; reply, resolve/reopen, comments panel, show-resolved filter (fnd_8) | M | InkPad has the annotation layer — anchored comments are a page-element like the text box, with a panel that lists threads by page |
| 7 | **App Intents for Siri/Shortcuts** | `CreateNoteIntent`, `NoteAppendTextIntent`, `OpenNoteIntent`, `SelectSubjectIntent`… (fnd_13) | S | "Start a new note in <folder>", "Add to my note" — great for capture; Swift Playgrounds supports App Intents |
| 8 | **Favorites + page bookmarks** | `PageBookmarked`, `Favorite Notes`, page manager bookmark per page (fnd_12) | S | Star notes and bookmark pages inside a note; surface in the library sidebar |

## Adopt as architecture (invisible but valuable)

| # | Idea | Evidence | How InkPad would benefit |
|---|------|----------|--------------------------|
| 9 | **Event-sourced op log as the document format** | `Op`, `Seq`, `AppendOpsEvent`/`ReceiveOpsEvent`/`AcknowledgeAppendedOpsEvent`, `LogicalTimeSorted`, typed ops per change (`CreateInk`, `ModifyInk`, `SetPageBackground`…) (fnd_2) | InkPad saves whole documents. An op log gives cheap per-change undo history, autosave diffs, and — later — iCloud conflict resolution that merges instead of last-write-wins. Start by persisting change records alongside the document; keep the doc format backward-compatible |
| 10 | **Design tokens / theme object** | `GLPersonality.PersonalityColors/Font/Radius/Spacing/Manager` + GLDesignSystem (fnd_14) | InkPad hardcodes colors and metrics in places. Centralize into one `Theme` (colors, radius, spacing, font) — makes dark mode and the Arabic RTL polish cheaper |
| 11 | **MyScript-style persisted recognition** | GLScript = MyScript engine; recognition stored per page and reused for search + conversion (fnd_5) | Same OCR result should feed "Copy as Text", "Make Editable Text", and search — compute once at stroke-settle, store, reuse everywhere (InkPad already shared helpers; push further) |

## Consider later / niche

- **Connectors between shapes with re-routing** (`ConnectorRouter`, arrow caps, `GLPathFinder`) — mind-map arrows; needs first-class shapes first (S2). (fnd_9)
- **Math box** (`+Math`, `Convert to Math`, `MathBlock`) — handwritten math → evaluated; needs a math recognizer (Vision doesn't do math) — hard without MyScript. (fnd_10)
- **Measurement tools** (calibrate scale, length/area of drawn objects) — study use-case; pure geometry on existing strokes. (fnd_9)
- **Gallery publishing** (tags, remix, moderation) — server-side product, not an app feature. (fnd_12)
- **Widget quick-capture** ("Start recording" tile) — depends on #2. (fnd_13)
- **Web clips** — snapshot a web page into the note; medium, needs a rendering path.

## Explicitly not worth copying

- 25-framework decomposition — InkPad is one Swift Playgrounds package; the *layering* (ink engine / model / UI / services) is the takeaway, not the split.
- PDFNet (38 MB, paid) — PencilKit + PDFKit serve InkPad fine.
- Analytics stack (Firebase, Mixpanel, Iterable, Apollo) — not applicable.

## Status (2026-11-15)

All ten Adopt items are in InkPad:

| # | Item | State |
|---|------|-------|
| 1 | Hold-to-perfect-shape | `Canvas/ShapeRecognizer.swift`, already shipped |
| 2 | Ink-linked audio | `Canvas/InkReplay.swift`, already shipped |
| 3 | Paper template pack | template gallery + `PageTemplate`, already shipped |
| 4 | Per-note OCR search index | recognized text persisted per note (`NoteFiles.textFile`) |
| 5 | Password-locked folders | `FolderLockGate` in `Views/NoteLock.swift` + `LibraryStore` folder locks; Face ID (or passcode) per session, subfolders inherit, notes leave search/Spotlight while locked (78093c3) |
| 6 | Threaded anchored comments | `Models/NoteComment.swift` as page elements + `Views/CommentViews.swift` (1d8eb70) |
| 7 | App Intents | `App/AppIntents.swift` (5e14ebb) |
| 8 | Favorites + bookmarks | already shipped |
| 9 | Op log | `Storage/NoteOpsLog.swift` (ab0aef8) |
| 10 | Design tokens | `Theme.Radius/Spacing/Colors` (ed6cd26) |

## Suggested batch order

1. **Batch N1 (quick wins):** paper-template pack (#3), favorites/bookmarks (#8), App Intents (#7).
2. **Batch N2 (one flagship):** shape recognition (#1) — biggest wow-per-effort, no new data model.
3. **Batch N3 (foundation):** per-note OCR search index (#4) + persisted recognition (arch #11).
4. **Batch N4 (big one):** ink-linked audio (#2) — flagship differentiator for lectures.
5. **Batch N5:** locked folders (#5), comments (#6), theme tokens (arch #10), op-log (arch #9).
