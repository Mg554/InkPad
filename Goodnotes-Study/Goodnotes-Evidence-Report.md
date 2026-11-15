# Investigation report

**Question:** How does the installed Goodnotes app work — what features does it ship and how is it structured internally — so that our own InkPad iPad app can benefit from its design and feature ideas?

**Purpose:** Learn from a shipped, successful note-taking app: map Goodnotes' feature set and architecture to find concrete, lawful ideas worth adopting in InkPad (our SwiftUI/PencilKit iPad note app).

**Done when:** An evidence-backed map of Goodnotes' architecture (bundle, frameworks, binary modules, services) and its shipped feature surface, ending in a ranked list of concrete features/structure ideas for InkPad with a note on how each would be built.

## What we looked at

- Goodnotes.app (A folder)
- Goodnotes (A Mac or iPhone program)
- /Applications/Goodnotes.app

## What we found

### Goodnotes 7.1.36 (bundle id com.goodnotesapp.x) declares a far richer document model than a simple notebook: its exported UTIs include outlines, tabs, pages, folders, folder-items, elements, images, text and lasso pasteboards, plus distinct package formats for collections (.collection), templates (.gntemplate), audio tape (.gntape), courses (.gncourse) and textbooks (.gntextbook) — and legacy .enote/.notes single-file notes alongside the zip-based .goodnotes package.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_19e2504ee7cee3c95429d2949bb1c49a78c070f55bf4c77ee7392f568783d2fe` — Info.plist (xml plist, bundle-info-plist) with 74 top-level key(s); bundle id com.goodnotesapp.x. (path=/Applications/Goodnotes.app/Contents/Info.plist)

### Goodnotes 7.1.36 is a Mac Catalyst build (platform mac-catalyst, minos 18.6.0, SDK 27.0) shipped as one 539 MB universal binary (x86_64 + arm64) that statically links its own product frameworks alongside Apple's: a GN6 design system (GN6DesignSystemFont/Color/ColorTokens), an on-device ML stack (onnxruntime + OnnxRuntimeBindings/Shared, CoreML), a handwriting stack (HandwritingBeautificationCore, HandwritingSynthesis, HandwritingCommon, GNHandwritingSynthesis, BaselineEstimation, Matft), GNSVG2PDF, WebRTC, RocksDB, gnyjsFFI, GNAILanguages, CryptoSwift/OpenSSL/CryptoKit, Lottie, AmplitudeCore and GNDRM — plus PencilKit, PDFKit, Vision/VisionKit, Speech, NaturalLanguage, CloudKit, WidgetKit, AppIntents, StoreKit, BackgroundTasks and FileProvider.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_7f210850fbf70226ef1fcfa4c7d3113a6f122989b7872a847530325a09f0fd74` — execute Goodnotes (arm64, 1 of 2 slices), 160 load commands, 140 libraries, 3 run paths, 12475 imports, 6062 exports, code-signed. (path=/Applications/Goodnotes.app/Contents/MacOS/Goodnotes)

### Goodnotes' Mac build is sandboxed with app groups, CloudKit + CloudDocuments iCloud containers, production push (aps-environment), Sign in with Apple, camera/microphone/photos/printing entitlements and 26 associated-domains applinks covering the main site, web, share, marketplace, classroom, CSAN publisher and org/edu admin hosts — i.e. the product spans consumer notes, sharing, a template marketplace, and an education/classroom platform.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_09e05203cf2973f27f66e069b3d5834936fd7a4a52edea44cc503ed1f65febca` — Goodnotes (arm64) is signed as com.goodnotesapp.x (team C88F57F4TJ); 1 code directory, 1 requirement(s), 22 entitlement(s); CMS signature VALID, binds the code directory, chain to Apple Root CA. (path=/Applications/Goodnotes.app/Contents/MacOS/Goodnotes)
  - `ev_19e2504ee7cee3c95429d2949bb1c49a78c070f55bf4c77ee7392f568783d2fe` — Info.plist (xml plist, bundle-info-plist) with 74 top-level key(s); bundle id com.goodnotesapp.x. (path=/Applications/Goodnotes.app/Contents/Info.plist)

### Goodnotes 7's content model is a versioned schema of typed note items, not loose data: PenStroke (v1 and v2, variable-width strokes with a flattened line/curve memory representation), Text (v1, v2 and a TextFragment variant), Image, Math, FillShape, FillPath, FillEllipse, SerializedShape, SerializedSticky and SerializedLine items, all funnelled through AnyNotesItemDescriptor. A dedicated NotesItemLayoutEngine produces Basic/Shape/Line notes-items-with-layout, an IncrementalNotesWithLayoutCache and a NotesItemWithLayoutTree (an item tree for hit-testing and rendering).

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_8e0ea6d67ee7c5fa4a7b7da1a49fe7d5d81077bd1bff70f28a85337d6b204ed9` — 54 Objective-C classes and categories matching "NotesItem".
  - `ev_7aa1c86cf44d8d3894dc7f570246f4663a070c5414069ca750ce14a7e778de97` — 98 Objective-C classes and categories matching "Schema".

### Goodnotes renders ink with a dedicated Metal renderer stack, not UIKit views: RendererInterface exposes a Rasterizer, MetalImageData/MetalImageBitmap, ImmutableIOData, SharedRendererView, Texture/DrawableOutputImage, a RendererAnimator and a RendererDecorator; RendererV4 adds a JobPlanner, AtlasTexture, StrokesCache, RendererEngine, RendererStatus and a MetalGPUContext (with a FakeCPUContext fallback). The app layer runs parallel New / Legacy / Unified renderer paths per tool (PenView, LassoView, EraserView, ElementsView, RealTimeView, RealTimePenView, RealTimeLaserPointerView, ImageToolView) plus a MinimapRenderer for a page minimap and a MetalColorPickerRenderer.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_da7bfb9de1a7d32a52cc49a8ed1623c578cfb2940f83c17bb0ba918258b63c7e` — 166 Objective-C classes and categories matching "Renderer".

### The notes store is layered and reactive: CommonCore provides InMemoryNotesStore, InMemorySyncNotesStore, AsyncInMemoryNotesStore, DBProvidedNotesStore, CachedRejectedNotesStore and InMemoryRejectedNotesStore, with NotesStoreAssetProvider, NotesStoreWriteObservation, NotesCommandHandlers/AsyncNotesCommandHandlers, ListNotesItemsSubscription(+Handler), AsyncNotesDeserializer and a WebVersionedNotesFetcher with WebDocumentNotesPreFetcher — i.e. an in-memory working copy, a durable database behind it, command-based mutation, push subscriptions for the UI and versioned prefetch for speed.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_1f2dfed4eea554fa8d8016abb8851db8efbd6f9c953d807f0ca8196816ffb08b` — 375 Objective-C classes and categories matching "Notes".

### The document core is event-sourced with an explicit schema lifecycle: the Schema module carries DocumentCreated, PageCreated, CourseCreated/Updated, ProblemCreated/Updated, TemplateCreated, DRMCreated and DocumentMigrated events, and CreateDocument / ImportDocument / ExportDocument / ExportPages / CreateProblem / CreateDRM commands, alongside FolderItem, ClassroomAssignment, CommentThread, RichTextRaw and InlineAttributesRaw. GoodNotesCore adds NotesItemMigration with per-type migrators (TypingNotesItemMigrator, TextBoxNotesItemMigrator), a DebugSchemaVersionOverride and LiveSchemaCompatibility — so schema versions are first-class and migrations are per-item-type.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_7aa1c86cf44d8d3894dc7f570246f4663a070c5414069ca750ce14a7e778de97` — 98 Objective-C classes and categories matching "Schema".
  - `ev_1f2dfed4eea554fa8d8016abb8851db8efbd6f9c953d807f0ca8196816ffb08b` — 375 Objective-C classes and categories matching "Notes".

### Goodnotes ships a large zoo of on-device Core ML models rather than sending ink to a server: CoMER encoder/decoder triples at 40/80/160 for mathematical-expression recognition from handwriting, Latin and Thai LSTM handwriting recognisers, HWWordGroupingPairwise and HWGroupingPairwise (grouping strokes into words and lines), ScribbleRecognizerModel, ScriptClassificationLSTM (script/language detection), LayoutClassifier, NER_fp16, HWBulletDetectionLSTM, a Denoiser_1536, BlockNEAT and V2BlockNEAT models for stroke/point prediction (beautification and vectorisation), and a document-classification ViT-tiny. The app also links onnxruntime and CoreML directly.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_07b46d4acc8c576f3c54d0ba695600f748274d95c595c70c717dae75d6ce9637` — Resources: nothing in it points to a runtime, not even a native program. (path=/Applications/Goodnotes.app/Contents/Resources)
  - `ev_7f210850fbf70226ef1fcfa4c7d3113a6f122989b7872a847530325a09f0fd74` — execute Goodnotes (arm64, 1 of 2 slices), 160 load commands, 140 libraries, 3 run paths, 12475 imports, 6062 exports, code-signed. (path=/Applications/Goodnotes.app/Contents/MacOS/Goodnotes)

### The AI surface is a credit-metered assistant built into the canvas: an 'Ask Goodnotes' sidebar that answers over the current page or a page range, with change-tone, create-image and diagram/flowchart generation, an agent math mode and lasso mode, AI-generated-content tags, a data-protection disclaimer and a credits balance. A separate AI Typing picker rewrites text (make longer/shorter, fix grammar and spelling, paraphrase, change tone, convert to bullet points) with its own quota. AITextbook and a NexusEnhanceMeetingNotesEvent extend AI to textbooks and meeting notes. The app also contains a CommonNLI agent that reads notes (GetStickyNotesAgentTool, NotesItemActionHandler, NotesRenderingSpecParser).

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_ed961a4f6be0f9fd5bbd527bec6af9089a7d70294340f588fd99b7860091200a` — LLMChat.strings: lines 1–1035 of 1035 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/LLMChat.strings)
  - `ev_70423f90c0284c0ce8f150a8876220837522609331cec4166de15214b0aec693` — AITyping.strings: lines 1–135 of 135 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/AITyping.strings)
  - `ev_389b48018d172f40411ddc45768344cd6b5017292f37b62ba5490ef2b1e0e453` — AITextbook.strings: lines 1–18 of 18 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/AITextbook.strings)
  - `ev_1f2dfed4eea554fa8d8016abb8851db8efbd6f9c953d807f0ca8196816ffb08b` — 375 Objective-C classes and categories matching "Notes".

### Audio is a first-class note medium: record with a clip name, playback speed control, noise reduction, export, and per-recording transcription, plus a notes-playback behaviour with three modes — spotlight, real-time reveal and static — meaning recorded audio can reveal the handwritten notes in sync as it plays.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_c9b3a5f1ba6e7c833f1b8ffb513500af1f070b202fa7097dc2fd5481fe4442d8` — GNAudioRecordings.strings: lines 1–180 of 180 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/GNAudioRecordings.strings)
  - `ev_b56ac717c6a6bfe8a907ea4129c09aa393c8acfec8426e960b3e70c402761d78` — Transcription.strings: lines 1–541 of 541 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/Transcription.strings)

### Goodnotes recognises handwritten mathematics and then does algebra on it: the Math Suggest menu offers solve, simplify, factorise, expand, multiply-with-conjugate, partial-fraction decomposition, canonical form, mixed/improper fraction and decimal forms, sum-of-logs-to-product, expand log, expand and linearise exponentials, arc-cos/sin/tan conversions, tan(x) to sin(2x) or cos(2x), half-tangent and trig expansion. Results can be copied as LaTeX, as the original handwriting or as an image, and the user can report a wrong solution or a graph that does not match the input.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_4c50c37cd0ce3f1134c3297e4beb3a9b8f9c20cb3bab8994a054b0ca934b1a23` — MathSuggest.strings: lines 1–199 of 199 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/MathSuggest.strings)
  - `ev_3f8021afe55feb6378a25199bcd12a88b4a191a027dcf57e0e6320b07fa070bf` — MathConversion.strings: lines 1–18 of 18 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/MathConversion.strings)

### Handwriting beautification is a shipped product with a review loop: the user can see the original, accept a restyle, rewrite the correction, and send structured feedback (incorrect content, layout issue, mismatched style, wrong colour, not readable, too slow).

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_75155b66356cba87c86191133c707c1f106d13d70c211aa16c2bc68144088dad` — HandwritingBeautification.strings: lines 1–130 of 130 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/HandwritingBeautification.strings)

### The canvas toolset is deeper than a pen and an eraser: the eraser has object, pixel, precision, segment and stroke modes plus filters (highlighter only, tape only) and auto-deselect; a Floating Layers panel manages named layers with their own notes; Draw-and-Hold has advanced options; the colour picker keeps presets, custom colours and a history; a 'Tape' tool masks areas with solid colour, gradients or uploaded patterns; and there are element collections of Back To School, Everyday Stickers, Mind Map Shapes, Sticky Notes and Text Stamps.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_ea43de4fb15ac17ecd19440a6cbfc66406968e70533ecbcf9b02bd09da7622ed` — Tools.strings: lines 1–947 of 947 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/Tools.strings)
  - `ev_6fd8fe2748ae27aeedc2458f1a8e312b025d0498d416c838e121872f0cbf3df3` — Tape.strings: lines 1–93 of 93 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/Tape.strings)
  - `ev_aa9653c39cfc7ae8f9aba5e2c924a869dafb195fce660f96c35ef006f4792335` — ElementCollection.strings: lines 1–6 of 6 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/ElementCollection.strings)

### Goodnotes 7 documents are organised as tabs inside a hierarchical folder tree, with a whiteboard as a first-class canvas type: the bundle declares exported UTIs for outline, tab, page, folder, folder-item, document and element, a GN6AppServices TabManager with DraggedTab, a root tab-bar controller, an ExamPrep and Learn layer (study sets, mock exams with an AI dashboard, practice categories), a Nexus block editor (headings 1-3, paragraph, bulleted/numbered/nested lists, check lists, code, quote), a whiteboard canvas with blank/dot-grid/square-grid backgrounds that converts into a notebook, and a content/template store with groups, colours, a marketplace and creator attribution.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_19e2504ee7cee3c95429d2949bb1c49a78c070f55bf4c77ee7392f568783d2fe` — Info.plist (xml plist, bundle-info-plist) with 74 top-level key(s); bundle id com.goodnotesapp.x. (path=/Applications/Goodnotes.app/Contents/Info.plist)
  - `ev_1dcce2caf0f441089603efba5d413b1d193e92c7ef66467daa1ee75cac05b231` — 127 Objective-C classes and categories matching "Tab".
  - `ev_4a4492fd217420975af6e0ea4dd348e80a00bcc39bad0f732628f6888ac3bb16` — Canvas.strings: lines 1–356 of 356 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/Canvas.strings)
  - `ev_ec5d988ca35665fbdf23ebf7ccb27d4ce9dd210e33a7b4d7fd22e98802e8dc95` — Nexus.strings: lines 1–156 of 156 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/Nexus.strings)
  - `ev_3a22b4a0e5cba4178b7de539d4bccb1c2c60e519ccbbf1c522b65089d6c10133` — ExamPrep.strings: lines 1–441 of 441 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/ExamPrep.strings)
  - `ev_5c6259de787086d64348e26f141f02ad4f021e28e26b3fcce0d423be5f206720` — Learn.strings: lines 1–387 of 387 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/Learn.strings)
  - `ev_d4c893d9069b0c047e0fff2132f310d7b300c26664b79b7d13234ff9e8ce7a3b` — TemplateLibrary.strings: lines 1–323 of 323 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/TemplateLibrary.strings)

### Goodnotes is keyboard-first and heavily accessible: 70 declared shortcuts covering page navigation, big-nudge moves, first/last page, zoom and fit-to-page, every writing tool (pen, pencil, highlighter, eraser, lasso, shape, text, image, laser, ruler, selection), find / find-next / find-previous, hiding the ruler and timer, camera, tabs, the elements panel, duplicate and delete page, read-only mode, toggle content panel, open AI, bring-to-front / send-to-back, and lock object.

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_bb86d811ddf00c11fd2050a61b7212467a2689af3f6728e3563c2cf4ea95bc06` — KeyboardShortcuts.strings: lines 1–209 of 209 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/KeyboardShortcuts.strings)
  - `ev_bd3f2cd2feafb30d67b920e49655564e8e0bbeab88bc369ecf76b63ba33a227f` — GN6ToolbarUI.strings: lines 1–215 of 215 (UTF-16LE). (path=/Applications/Goodnotes.app/Contents/Resources/en.lproj/GN6ToolbarUI.strings)

## Open questions

- What exactly is 'Nexus' — is it a new block-based notebook format, a separate document type, or the replacement for the classic page canvas in Goodnotes 7? _(severity Medium, Open)_
  - would settle it: Read Nexus.strings values (not just keys) to see how it describes itself
  - would settle it: Inspect GN6App.NexusEnhanceMeetingNotesEvent and the Nexus module's own types
- Is the Floating Layers panel a per-canvas layer model that InkPad could adopt, and what is shared between layers? _(severity Low, Open)_
  - would settle it: Read the Tools.strings values around floating_layers_* for behaviour
  - would settle it: Look for a Layer type in the Schema or NotesItems modules
- Does the Goodnotes 7 .goodnotes package keep ink as PencilKit PKDrawing data, or in Goodnotes' own PenStrokeNotesItem format with its own variable-width stroke encoding? The answer decides whether InkPad could open Goodnotes files directly or only export to PDF/images. _(severity High, Open)_
  - would settle it: Open a real .goodnotes package with core_target_open and inspect its contents for .goodnotes/canvas/ or Pages/ Ink files
  - would settle it: Inspect the Schema.PenStrokeNotesItem fields and compare them with PKStroke's fields
- How much of the AI feature set runs fully on-device versus calling Goodnotes' servers? The on-device Core ML models cover handwriting and beautification, but 'Ask Goodnotes' shows credits and quota errors, which implies a metered server-side model. _(severity Medium, Open)_
  - would settle it: Look for network endpoints called by GN6AppServices.GoodnotesAIProvider
  - would settle it: Check whether LLMChat strings mention a local model or an on-device extension

## How this was done

- **Mode:** Deep (the original's code and files could be read)
- **Engines:** builtin
- **Limitations:**
  - 89 symbolic link(s) were noted by name only; what they point at wasn't read.
  - A file being in the folder doesn't prove the app runs it: it may be unused, left over from an update, or there for another reason. Nothing was started, so these are inferences.
  - Authenticity is verified cryptographically (the CMS signature over the signed attributes, that the signed messageDigest covers the CodeDirectory, and the certificate chain's internal links); certificate revocation (OCSP/CRL), signing-time validity against a trusted timestamp, and full Apple notarization/policy evaluation are NOT checked.
  - DER-encoded entitlements are present; their size is reported, the XML form is decoded.
  - Only names, the ends of some files and the start of the main programs were read. The app's contents weren't unpacked or analysed; next_steps says what to run for that.
  - Read from the file only; nothing was loaded or run.
  - The file is read as text as it is stored: nothing is run, rendered or formatted, and text a program builds or downloads while it runs isn't here.
  - classes registered at run time (objc_allocateClassPair) are not listed
  - max_entries (20000) or max_depth (3) stopped the walk, so what's further in wasn't seen. Raise them to see more.
  - max_entries (400) or max_depth (1) stopped the walk, so what's further in wasn't seen. Raise them to see more.
  - types are classified from the mangled names without a full demangler; nested generic types may be misfiled

## Evidence ledger

- `ev_459be8bf97932634a225a37af7944006a33c06539bf58997238c437a05a15116` **app_folder_explain** — Goodnotes.app: its programs are native code; no bigger runtime was recognised. (Best guess)
- `ev_19e2504ee7cee3c95429d2949bb1c49a78c070f55bf4c77ee7392f568783d2fe` **apple_plist_show** — Info.plist (xml plist, bundle-info-plist) with 74 top-level key(s); bundle id com.goodnotesapp.x. (Seen it)
- `ev_09e05203cf2973f27f66e069b3d5834936fd7a4a52edea44cc503ed1f65febca` **apple_signature_show** — Goodnotes (arm64) is signed as com.goodnotesapp.x (team C88F57F4TJ); 1 code directory, 1 requirement(s), 22 entitlement(s); CMS signature VALID, binds the code directory, chain to Apple Root CA. (Seen it)
- `ev_d1f707cc4b85919a29136838b20cf0840bd4766bfb9af694890128f5c98e5635` **apple_slices_list** — Goodnotes is a universal binary with 2 slices: x86_64, arm64. (Seen it)
- `ev_7f210850fbf70226ef1fcfa4c7d3113a6f122989b7872a847530325a09f0fd74` **apple_macho_show** — execute Goodnotes (arm64, 1 of 2 slices), 160 load commands, 140 libraries, 3 run paths, 12475 imports, 6062 exports, code-signed. (Seen it)
- `ev_91e5d7a3c77f4f3a4c9e5227e67198a2b4a3961b0e723ff0de7ae6bc57458682` **apple_swift_types_list** — 10691 Swift symbols describing 1038 types. (Best guess)
- `ev_ea43de4fb15ac17ecd19440a6cbfc66406968e70533ecbcf9b02bd09da7622ed` **core_text_read** — Tools.strings: lines 1–947 of 947 (UTF-16LE). (Seen it)
- `ev_ed961a4f6be0f9fd5bbd527bec6af9089a7d70294340f588fd99b7860091200a` **core_text_read** — LLMChat.strings: lines 1–1035 of 1035 (UTF-16LE). (Seen it)
- `ev_3f8021afe55feb6378a25199bcd12a88b4a191a027dcf57e0e6320b07fa070bf` **core_text_read** — MathConversion.strings: lines 1–18 of 18 (UTF-16LE). (Seen it)
- `ev_c9b3a5f1ba6e7c833f1b8ffb513500af1f070b202fa7097dc2fd5481fe4442d8` **core_text_read** — GNAudioRecordings.strings: lines 1–180 of 180 (UTF-16LE). (Seen it)
- `ev_4a4492fd217420975af6e0ea4dd348e80a00bcc39bad0f732628f6888ac3bb16` **core_text_read** — Canvas.strings: lines 1–356 of 356 (UTF-16LE). (Seen it)
- `ev_bd3f2cd2feafb30d67b920e49655564e8e0bbeab88bc369ecf76b63ba33a227f` **core_text_read** — GN6ToolbarUI.strings: lines 1–215 of 215 (UTF-16LE). (Seen it)
- `ev_75155b66356cba87c86191133c707c1f106d13d70c211aa16c2bc68144088dad` **core_text_read** — HandwritingBeautification.strings: lines 1–130 of 130 (UTF-16LE). (Seen it)
- `ev_4c50c37cd0ce3f1134c3297e4beb3a9b8f9c20cb3bab8994a054b0ca934b1a23` **core_text_read** — MathSuggest.strings: lines 1–199 of 199 (UTF-16LE). (Seen it)
- `ev_6fd8fe2748ae27aeedc2458f1a8e312b025d0498d416c838e121872f0cbf3df3` **core_text_read** — Tape.strings: lines 1–93 of 93 (UTF-16LE). (Seen it)
- `ev_3a22b4a0e5cba4178b7de539d4bccb1c2c60e519ccbbf1c522b65089d6c10133` **core_text_read** — ExamPrep.strings: lines 1–441 of 441 (UTF-16LE). (Seen it)
- `ev_8b905a0f0b1bcc35760ae4d472999b8db9a38bb5405d591ec1e8982849dcd8a6` **core_text_read** — TimeKeeper.strings: lines 1–201 of 201 (UTF-16LE). (Seen it)
- `ev_b56ac717c6a6bfe8a907ea4129c09aa393c8acfec8426e960b3e70c402761d78` **core_text_read** — Transcription.strings: lines 1–541 of 541 (UTF-16LE). (Seen it)
- `ev_aa9653c39cfc7ae8f9aba5e2c924a869dafb195fce660f96c35ef006f4792335` **core_text_read** — ElementCollection.strings: lines 1–6 of 6 (UTF-16LE). (Seen it)
- `ev_58b3004fbe652f1ce22ae727fb1dae6013028b0ebd3405125b84af3b013af8c8` **core_text_read** — WritingAids.strings: lines 1–82 of 82 (UTF-16LE). (Seen it)
- `ev_54741e6267f9699dd2c66df2c95148fa064eacf3f4557f3f672bd8c87e8a1eb7` **core_text_read** — Canvas.strings: lines 1–5 of 356 (UTF-16LE). (Seen it)
- `ev_5c6259de787086d64348e26f141f02ad4f021e28e26b3fcce0d423be5f206720` **core_text_read** — Learn.strings: lines 1–387 of 387 (UTF-16LE). (Seen it)
- `ev_ec5d988ca35665fbdf23ebf7ccb27d4ce9dd210e33a7b4d7fd22e98802e8dc95` **core_text_read** — Nexus.strings: lines 1–156 of 156 (UTF-16LE). (Seen it)
- `ev_2fd4ca71e46b2498c988f125d72e53100907dad681d7f8670aa81dee4d5fd11a` **core_text_read** — Search.strings: lines 1–11 of 11 (UTF-16LE). (Seen it)
- `ev_d327c870077f747d8f5bed6636f2f3da559b82f37d1769a026f300f80126a865` **core_text_read** — Import.strings: lines 1–39 of 39 (UTF-16LE). (Seen it)
- `ev_b48b237967db366a1e837f848add6cb01241e48b3efb0f32ade3bef897e48ca9` **core_text_read** — ContentStore.strings: lines 1–561 of 561 (UTF-16LE). (Seen it)
- `ev_d4c893d9069b0c047e0fff2132f310d7b300c26664b79b7d13234ff9e8ce7a3b` **core_text_read** — TemplateLibrary.strings: lines 1–323 of 323 (UTF-16LE). (Seen it)
- `ev_389b48018d172f40411ddc45768344cd6b5017292f37b62ba5490ef2b1e0e453` **core_text_read** — AITextbook.strings: lines 1–18 of 18 (UTF-16LE). (Seen it)
- `ev_70423f90c0284c0ce8f150a8876220837522609331cec4166de15214b0aec693` **core_text_read** — AITyping.strings: lines 1–135 of 135 (UTF-16LE). (Seen it)
- `ev_bb86d811ddf00c11fd2050a61b7212467a2689af3f6728e3563c2cf4ea95bc06` **core_text_read** — KeyboardShortcuts.strings: lines 1–209 of 209 (UTF-16LE). (Seen it)
- `ev_1a2b996b44d2254c24921f4996ca229683c4959b4dbe163b5661b3ae1268501b` **core_text_read** — GN6Settings.strings: lines 1–497 of 497 (UTF-16LE). (Seen it)
- `ev_5de8cb69019021c986665f3b844cc265da451c7d7171fcac69630309e0956710` **core_text_read** — LibrarySettings.strings: lines 1–3 of 3 (UTF-16LE). (Seen it)
- `ev_57829a53978fc05cd6e03368853cac4ddd859a1c75dc57fe6821378e92f0834d` **core_text_read** — InfoPlist.strings: lines 1–23 of 23 (UTF-16LE). (Seen it)
- `ev_3a650d13290043143129f9da06acee4f82c5e5ac86120782f95064f5f2b6b58f` **core_text_read** — Migration.strings: lines 1–96 of 96 (UTF-16LE). (Seen it)
- `ev_7aa1c86cf44d8d3894dc7f570246f4663a070c5414069ca750ce14a7e778de97` **apple_objc_classes_list** — 98 Objective-C classes and categories matching "Schema". (Seen it)
- `ev_1dcce2caf0f441089603efba5d413b1d193e92c7ef66467daa1ee75cac05b231` **apple_objc_classes_list** — 127 Objective-C classes and categories matching "Tab". (Seen it)
- `ev_8e0ea6d67ee7c5fa4a7b7da1a49fe7d5d81077bd1bff70f28a85337d6b204ed9` **apple_objc_classes_list** — 54 Objective-C classes and categories matching "NotesItem". (Seen it)
- `ev_da7bfb9de1a7d32a52cc49a8ed1623c578cfb2940f83c17bb0ba918258b63c7e` **apple_objc_classes_list** — 166 Objective-C classes and categories matching "Renderer". (Seen it)
- `ev_1f2dfed4eea554fa8d8016abb8851db8efbd6f9c953d807f0ca8196816ffb08b` **apple_objc_classes_list** — 375 Objective-C classes and categories matching "Notes". (Seen it)
- `ev_80d185044aca58ec36d1ef228b6cfdf9642455f720833a9c408cb81fe088469d` **apple_objc_classes_list** — 223 Objective-C classes and categories matching "Event". (Seen it)
- `ev_07b46d4acc8c576f3c54d0ba695600f748274d95c595c70c717dae75d6ce9637` **app_folder_explain** — Resources: nothing in it points to a runtime, not even a native program. (Best guess)

