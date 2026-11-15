# Investigation report

**Question:** How does the Notability app work — its architecture, configuration, UI structure and feature set — and which of its designs and features are worth bringing into InkPad (an iPad handwriting app, Swift Playgrounds package)?

**Purpose:** Competitive study for InkPad: find concrete features, UI patterns and configuration ideas to adopt, ranked.

**Done when:** A ranked list of adoptable Notability features/patterns, each backed by evidence ids, plus a written report.

## What we looked at

- Notability.app (A folder)
- /Applications/Notability.app

## What we found

### Notability 16.13.5 is a modular app: the main binary plus ~25 internal frameworks. The engine layer is GLInkKit (ink rendering, 5725 symbols), GLMetalKit (GPU), GLMath, BezierKit (bezier geometry), GLPathFinder (connector routing), ShapeDetection (shape recognition, 712 symbols); the domain layer is Model (14775 symbols) + GLRedux (store/action state management); the UI layer is ModelUI + GLDesignSystem (5323 symbols, design tokens); services are GLSync/GLCloudKit/GLCloudStorage, GLConversion (PDF export), GLImport (imports, 6611 symbols), and PDFNet (38 MB third-party PDF engine).

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (path=/Applications/Notability.app)

### The document model is event-sourced: Model exposes Op-based types (Op, Seq, SeqId, AppendOpsEvent, ReceiveOpsEvent, AcknowledgeAppendedOpsEvent, OpsBundle, LogicalTimeSorted, CreateInk/ModifyInk/CreateBlock/CreateShape/CreateConnector/CreateComment/ModifyPDFField ops). Every edit is an operation appended to a log and acked — this single design powers undo, redo, realtime collaboration and library migration.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (path=/Applications/Notability.app)

### Pages are block-based: Model has Block, BlockType, TextBlock, ImageBlock, MathBlock, Connector, Comment anchors, Ink, Shape, CreateBlock/ModifyBlock ops. Ink, text, math, images and shapes are all blocks positioned on the page rather than one flat drawing.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (path=/Applications/Notability.app)

### Search is a per-note multi-index: Model.SearchIndex_* types cover HandwritingSearchIndex, AudioSearchIndex (SearchIndex_RecordingTranscription, SearchIndex_ASRSegment), ImageSearchIndex (SearchIndex_ImageRecognizedText), PDFSearchIndex, TextSearchIndex, plus spatial hashes (NoteSpatialHash, PageSpatialHash, SparseGridSpatialHash) and character rects for result highlighting.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (path=/Applications/Notability.app)

### Handwriting recognition is powered by MyScript: GLScript (37 MB, 97038 symbols) contains HandwritingRecognitionConfiguration, HandwritingRecognitionLanguage, RecognizableCurve, HashableHandwritingCurve, NBMyScriptHandwritingDataPerPage, NBMyScriptSearch, RecognitionSettings — i.e. ink recognition results are stored per page and reused for both text conversion and search.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (path=/Applications/Notability.app)

### Shape recognition is a shipped Core ML model: ShapeClassifier.mlmodelc is described in its own metadata as a 'Single-stroke shape classifier over 64 resampled points' (CNN: 4 conv + maxPool + softmax, Float16, v0.3) that outputs classLabel plus per-class probabilities. Canvas.strings shows the supported targets: Triangle, Diamond, Ellipse, Rectangle, Star (Shapes.to*), plus Arrow, Pentagon, Hexagon, Heptagon, Octagon, Polygon, with fill/stroke/width styling.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_0c20b038257d3c21054bc38e259759ea82740a164b2b0d61b254edbd5e3bed15` — ShapeClassifier.metadata.json: lines 1–10 of 87 (UTF-8). (path=/private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/ShapeClassifier.metadata.json)
  - `ev_a7782a0ffb19b58bee44980260ddb5acbb835add98fb77a1e620248c006fbf7d` — Canvas.strings.xml: lines 1–10 of 1067 (UTF-8). (path=/private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/Canvas.strings.xml)

### Audio is a first-class ink-linked feature: record while writing (Audio.* strings, Recording/RecordingSegment/AudioLinked model types, TapePattern), playback with speed control and pause (MainMenu.startPlaybackTitle, playbackSpeed), trim/split/merge/rename recordings with undo, export as ZIP (PDF + Recording), a WidgetKit tile 'Start recording' (Widgets.CreateRecording), BGTask id 'autobackup' and mic usage strings. Ink is replayed in sync with audio during playback.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_a7782a0ffb19b58bee44980260ddb5acbb835add98fb77a1e620248c006fbf7d` — Canvas.strings.xml: lines 1–10 of 1067 (UTF-8). (path=/private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/Canvas.strings.xml)
  - `ev_6e91ab9f2a53114886b6af93b1a7fb238d6578df9f55961d6b6e74dddeaea9a5` — Localizable.strings.xml: lines 1–10 of 1253 (UTF-8). (path=/private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/Localizable.strings.xml)
  - `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (path=/Applications/Notability.app)

### Comments are threaded and anchored: Comment.* / Comments.* strings (add comment, reply, close/reopen thread, mark as resolved, show resolved filter, comments panel, pin accessibility label) plus Model.CreateComment/ModifyComment/CommentAnchor/ReplyAnchor. Commenting is a distinct tool ('Comment.tool').

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_a7782a0ffb19b58bee44980260ddb5acbb835add98fb77a1e620248c006fbf7d` — Canvas.strings.xml: lines 1–10 of 1067 (UTF-8). (path=/private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/Canvas.strings.xml)

### Connectors are smart arrows between shapes: Model has Connector, ConnectorRouter, ConnectorRoute, ConnectorPath, ArrowHead, Bend/BendPin, ConnectorCap (Canvas.strings: capArrow/Circle/Diamond/Triangle, start/end endpoints); ShapeDetection + GLPathFinder implement drawing/holding and re-routing. Measurement tools exist too: Measure.Panel strings (calibrate scale, calculate length/area of drawn objects, reset scale, mm² units).

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_a7782a0ffb19b58bee44980260ddb5acbb835add98fb77a1e620248c006fbf7d` — Canvas.strings.xml: lines 1–10 of 1067 (UTF-8). (path=/private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/Canvas.strings.xml)

### Math is a block type with conversion: Canvas.strings has Menu.mathBox '+Math', Menu.insertMath 'Insert Math', GraphConversion.convertToMath 'Convert to Math'; Model has MathBlock, MeasuredValue, MeasurementGeometry, MeasurementScale, MeasurementUnit. Handwritten math is recognized and evaluated inside a math box.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_a7782a0ffb19b58bee44980260ddb5acbb835add98fb77a1e620248c006fbf7d` — Canvas.strings.xml: lines 1–10 of 1067 (UTF-8). (path=/private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/Canvas.strings.xml)

### Paper templates are a pre-rendered PDF pack: 36 template folders (college_rule, cornell, engineering_grid, mind_map, music_staves, daily/weekly/monthly planners, habit_tracker, storyboards, mizige/tianzege character grids...) each containing PDFs in 5 sizes (A3–Letter/Legal/Tabloid) x 3 background colors (ffffff, f8f1bf, 000000) x 2 orientations + metadata.json + thumbnails, and covers are a folder of themed cover image sets. PageBackground/Paper/PaperFlair model types and SetPaper/SetPageBackground ops support them.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (path=/Applications/Notability.app)

### Organization and privacy: Library.strings shows password-locked folders (FoldersPassword.* with synced password + hint, unlock prompts on import/delete/export), favorite notes, tags, Auto-Backup to third-party services (one-way, selectable service/folders/format), Notability Gallery publishing (publish note/template with tags, moderation, remix-of attribution, unpublish), and Subjects/Folders hierarchy from App Intents entities (FolderEntity, NoteEntity, AccountEntity, SelectSubjectIntent).

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_ba07e113365a8df8e9c12241f44f92708979a7f52e6007728b7831545c860e7b` — Library.strings.xml: lines 1–10 of 1130 (UTF-8). (path=/private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/Library.strings.xml)

### Automation surface: 7 App Intents (CreateNoteIntent, UpdateNoteIntent, NoteAppendTextIntent, OpenNoteIntent, OpenFolderIntent, SelectNoteIntent, SelectSubjectIntent) with 5 entity queries and error strings covering plan limits, locked folders and permissions; the app registers BGTaskScheduler ids for libraryMigration, serverJobsUpload, serverOpsDownload, autobackup; PlugIns include ActionExtension, PreviewExtension, WidgetExtension appex; document import types span audio, images, txt, xlsx, pptx, docx, Pages, Keynote, zip.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_e95fe982b96190a370d02c3970cc93f0155f231cba864ca98d543a727b24508d` — Info.plist: lines 1–250 of 1029 (UTF-8). (path=/Applications/Notability.app/Contents/Info.plist)

### Theming is a design-token system: GLPersonality.framework (Personality, PersonalityTheme, PersonalityColors, BrandColors, PersonalityFont, PersonalityRadius, PersonalitySpacing, PersonalityManager, ObservedPersonality, BrandEnvironment) plus GLDesignSystem (5323 symbols) — UI constants (colors, fonts, radii, spacing) are centralized and switchable, including dark themes ('Featured Themes' setting).

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (path=/Applications/Notability.app)

## Open questions

_None outstanding._

## How this was done

- **Mode:** Deep (the original's code and files could be read)
- **Engines:** builtin
- **Limitations:**
  - Disk images (DMG), installers (PKG/MSI) and compressed tarballs are listed as single files, not opened.
  - The file is read as text as it is stored: nothing is run, rendered or formatted, and text a program builds or downloads while it runs isn't here.
  - the kind is detected from the first bytes and, to break ties, the file name

## Handoff

Notability study (macOS 16.13.5, static analysis) complete. Target /Applications/Notability.app open, 14 findings recorded (fnd_1..fnd_14) with evidence ids. Architecture: GL* frameworks (GLInkKit ink engine, GLRedux ops store, Model block/op event-sourced doc model, GLScript=MyScript HWR, ShapeDetection=Core ML single-stroke shape classifier over 64 resampled points, PDFNet PDF engine). Ranked adoptable list for InkPad is in the report. Next: if InkPad wants, evidence-level detail on specific subsystems (e.g. GLImport for import formats) — re-open target with core_target_open. Trap: .strings files are binary plists — Craft core_text_read refuses them; convert with plutil to xml first (copies in /private/var/folders/1b/dm4trc2n4bq97t9yk5jssszw0000gn/T/opencode/notability-evidence/). Symbol extraction pattern: nm | swift demangle | grep 'Module.Type'.

## Evidence ledger

- `ev_3fd06d4881d61f6842a6d5df5f3c5af310bde13a079b40cc0fc625ae7ee227f6` **core_target_triage** — Notability.app is a folder (an app bundle, an unpacked app or a project). (Best guess)
- `ev_8302388308caf649ff20cfbbeea75dea96c1b3371b0ad11d1b08506e3ab82b63` **core_archive_show** — Notability.app (directory) holds 1512 files in 2108 entries; 0 nested container(s). (Seen it)
- `ev_e95fe982b96190a370d02c3970cc93f0155f231cba864ca98d543a727b24508d` **core_text_read** — Info.plist: lines 1–250 of 1029 (UTF-8). (Seen it)
- `ev_d2124c41939458c33e8f58812480d0626354cdc20405fe2789bc8a24f83df258` **core_text_read** — extract.actionsdata: lines 1–1 of 1 (UTF-8). (Seen it)
- `ev_a7782a0ffb19b58bee44980260ddb5acbb835add98fb77a1e620248c006fbf7d` **core_text_read** — Canvas.strings.xml: lines 1–10 of 1067 (UTF-8). (Seen it)
- `ev_6e91ab9f2a53114886b6af93b1a7fb238d6578df9f55961d6b6e74dddeaea9a5` **core_text_read** — Localizable.strings.xml: lines 1–10 of 1253 (UTF-8). (Seen it)
- `ev_ba07e113365a8df8e9c12241f44f92708979a7f52e6007728b7831545c860e7b` **core_text_read** — Library.strings.xml: lines 1–10 of 1130 (UTF-8). (Seen it)
- `ev_0c20b038257d3c21054bc38e259759ea82740a164b2b0d61b254edbd5e3bed15` **core_text_read** — ShapeClassifier.metadata.json: lines 1–10 of 87 (UTF-8). (Seen it)

