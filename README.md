# InkPad

A free, private, Notability-style note-taking app for iPad, built as a
**Swift Playgrounds** app (SwiftUI + PencilKit). All notes stay on your iPad;
the optional AI study features send only the notes you study to the AI
service you choose, with your own API key.

## Status

Done:

- Library: nested folders with colors, notes grid with thumbnails, title
  search, quick actions (New Note, Import a File, Find a Template)
- Floating toolbar combining Notability and Apple Notes: realistic pens
  (quill, fountain pen, pen, monoline, pencil, crayon, watercolor, marker,
  highlighter), eraser (pixel or whole stroke), text, lasso, insert menu,
  ruler, finger drawing; per-tool colors plus custom colors, three widths
  per tool with a smooth 1-20 width bar and preview
- Movable toolbar: drag its handle, or any empty part of the bar, to any
  edge of the screen (top, bottom, left or right, at the start, middle or
  end). On the left or right it
  stands upright with the pens pointing at the page, and the page makes
  room for it. Collapse it to a pill or hide it completely (More › Hide
  Toolbar / Move Toolbar)
- Eraser "Back to Last Tool" (on by default): after an erase, InkPad
  switches straight back to the tool you used before
- Notability-style highlighter: even, see-through, pressure-independent
- Pressure sensitivity per pen: switch it off to keep the width even
- Hold to snap: rest the pencil at the end of a stroke and it turns into a
  straight line, circle, ellipse, triangle, rectangle or polygon while you
  are still holding (the highlighter snaps straight)
- Workspace (Notion-style): Planner with Board (drag between columns),
  List and Calendar views; Expenses with income, monthly budget,
  interactive category chart, budget rings, category bars and a
  day-by-day chart with the budget pace, currency and optional decimals;
  Mind Maps with drag, pinch-zoom and one-tap tidy layout
- Expenses › Customize (brush): Glass, Neon, Minimal or Paper charts,
  which charts show, a glow you tune (on/off, color, strength, size) and
  a background of its own (theme, plain, old paper, glass or a season)
- Mind Maps › Customize: ready styles (Spring Tree, Autumn Tree, Organic,
  Org Chart, Notebook, Dreamy) or mix your own: layout (free, growing
  right, both sides, radial, a real tree on a trunk, org chart),
  branches (curved, organic tapered, straight, elbow, wooden), idea
  shapes (capsule, rounded, box, circle, cloud, leaf, underline, text
  only; each idea can have its own), colors, font, glow, spacing and
  background. Write an idea by hand ("Write by Hand"); or Sketch & Reshape:
  draw the whole map freely with the pencil, and Reshape reads the
  writing and the lines you drew (on the iPad) and turns it into a tidy
  map in the layout you pick, keeping your handwriting if you like; "Let
  AI Organize It" sends only the ideas' words to your AI service
- Refine Handwriting (the wand in the drawing toolbar): smooths strokes
  when the pencil lifts, levels a slanted line and evens out word sizes
  after a pause; each can be turned on or off. Lasso › Refine does it for
  writing already on the page
- Apple Pencil double-tap switches to the eraser and back
- Audio recording synced with your writing, like Notability: record while
  you write; when you play a recording, writing that came later is faded
  and appears as the audio reaches it; tap your writing to hear what was
  said at that moment; skip, scrub, playback speed, rename, share and
  delete recordings
- Slides, like NotebookLM's slide decks: make a presentation from one or
  several notes (handwriting and PDF text are read on the iPad with
  Vision). Choose Detailed Deck or Presenter Slides, length, a focus and
  one of six themes. The AI service you connect (or Apple Intelligence on
  iPadOS 26) writes the slides; without AI, InkPad's own offline outliner
  builds them from your headings, lists and key sentences. Edit any slide,
  present full screen with a laser pointer, speaker notes and narration
  read aloud, and export as an editable PowerPoint file (.pptx, which also
  opens in Keynote and Google Slides) with speaker notes, a PDF, PNG
  pictures or a Markdown outline, or save the deck as a note to write on
- Study with AI, like Notability's: chat with your notes (answers stream in
  and name the notes they come from; every conversation is saved with its
  note, to read and continue later), flashcards with spaced review ("N
  flashcards ready for review"), multiple-choice quizzes, Smart Notes
  (organized study notes saved as a text note) and slides, for all notes
  or the ones you select. Works with Claude (Anthropic), ChatGPT (OpenAI),
  Gemini, OpenRouter, Groq, DeepSeek, Mistral, any OpenAI-compatible
  service, or Apple Intelligence on the iPad. Set it up in Study with AI ›
  AI Settings: pick the service, paste your API key (kept in the iPad's
  keychain) and tap Test Connection
- Write → Think → Build: circle writing (or PDF text) with the lasso and
  tap Think. Check the words read from your handwriting, then make
  Concepts, Flashcards, Questions (with answers) or an Explanation with
  your AI service; save the result as a text note in "Thinking" (linked
  back to the note) or add the cards to your flashcards
- AI Firewall: "AI Access" on any note or folder (in its menu, or in
  AI Settings › AI Firewall): Allowed, This iPad Only (only Apple
  Intelligence on the iPad may read it; nothing goes online) or Never. It
  covers chat, flashcards, quizzes, Smart Notes, Think and slides; a
  folder's level covers its subfolders' notes, and the strictest level
  wins. Slides from protected notes are outlined on the iPad
- Explain This: in Think, "Add to Page" places the answer as a text box
  right under the circled writing
- Messy Mode: in a text note, ⋯ › Organize This… sorts messy writing into
  headings, lists and tasks without changing what it says. Replace the
  note (the messy version goes to Recently Deleted) or save it as a new
  note
- Voice → Timeline: in the playback bar, the timeline button turns a
  recording into text on the iPad (Apple speech recognition, on-device
  only) with chapters: named by your AI service when the AI Firewall
  allows it, otherwise outlined on the iPad. Tap a chapter or a line to
  play from there, or search a word ("PEEP") to jump to where it was said;
  save the transcript as a text note
- Memory Heatmap (Study): each flashcard deck as a tile from red to green
  showing how much of it you likely remember now, with "You're forgetting…"
  for the weakest topic
- Handwriting search: handwritten and PDF notes are read with Vision after
  you edit them, and the library search finds their words
- Rotating the iPad keeps the page steady, with the same part of the page
  in the middle
- Lasso (Notability-style): circle ink, drag it, and use Style (size 1-20,
  solid/dashed/dotted, colors), Think, Copy as Text (handwriting read with
  Vision), Duplicate, Cut, Copy, Paste and Delete. On PDF pages, circle
  printed text to Copy Text or Highlight it
- Laser pointer for explaining, like Notability's: a smooth glowing line
  that stays while you point and fades softly after you lift the pencil,
  or with Tail on a short trail that follows it; four colors; never saved
  (AirPlay mirroring shows it on a projector or TV)
- Customize Toolbar (gear button): show or hide each tool and drag to
  reorder them, like Notability's Toolbox
- Width bar: the size follows the pencil smoothly along 20 levels on an
  even (geometric) scale, with a preview at the real size
- Text boxes: tap the page with the Text tool; bold, italic, underline,
  strikethrough, size, color, bulleted lists; move and resize. Type with
  the keyboard, or switch to "Write with Pencil" (in the toolbar or the
  keyboard's shortcut bar) to handwrite and have it turned into text. In the
  sidebar's circle menu, "Tapping a Text Field with Apple Pencil" sets
  every text field in InkPad to open the keyboard (default) or to take
  handwriting. "Show Keyboard" (text boxes, slide editor) brings it up and
  explains why if iPadOS keeps it hidden, for example when a hardware
  keyboard is connected
- Appearance: Match iPad, Light or Dark (the circle button at the top of
  the sidebar); pages keep their paper color
- Themes (the brush button at the top of the sidebar): nine themes
  (Classic, Paper, Midnight, Ocean, Forest, Sepia, Rose, Nord, Sunset) for
  backgrounds, sidebar and accent color, in light and dark. The Theme
  Mixer takes each part from any theme: colors, accent, plain or glass
  background (soft blended colors), glass colors and paper; mixes can be
  saved. Hybrid paper: new notes start on the theme's paper and each note
  can still change its own. Also the app font (Standard, Rounded, Serif,
  Mono), the typing font and size for text typed with the keyboard, and
  note card size. Season themes (Spring, Summer, Autumn, Winter) draw
  grass, flowers, leaves or snow at the edges with falling petals,
  leaves or snow (can be turned off). Glass has hue, strength and blur
  sliders, and Glass Cards makes tiles frosted
- Reminders (sidebar): Apple Reminders inside InkPad, with Today,
  Scheduled, All, Priority and Completed, your lists, dates, times and
  alerts (sent by the Reminders app), priorities and notes. Link a
  reminder to a note; "Remind Me…" in a note's menu, or circle writing
  with the lasso and tap Remind Me. Customize: glass, gradient or minimal
  tiles, row spacing, the done button's shape, a small celebration, glow,
  a background, and each list's color and icon or emoji (Edit List)
- Flowmodoro (from the Pythonation/flowmodoro-wep-app web app): a task
  list; tap a task to start the work stopwatch, stop when your focus fades
  and you earn a break of 5% of the work time (at least a minute; 10, 15
  or 20% can be chosen), with a sound when it ends.
  Edit, complete, reorder and delete tasks, and see every session in the
  history with today's total focus time
- Photos and images from Files placed on pages; move and resize
- Templates: Plain, Lined, Grid, Dot, Hexagonal Grid, Cornell Note,
  College Rule, Manuscript, Two and Three Column; six paper colors
- PDF import (one or several files), writing and highlighting on PDF pages
- Quick export, or "Export as..." with background paper, page margins,
  page range and password options
- Page sidebar with thumbnails (insert a blank page after any page, delete
  pages, reorder pages by dragging or with Move Up/Down; the writing moves
  with its page), page counter with previous/next
- Recently Deleted (sidebar): deleted notes are kept for 30 days; restore
  them or delete them for good
- Undo / redo for ink; autosave in the background
- Obsidian-style text notes: Markdown with live highlighting, edit/split/
  preview, `[[links]]` (unresolved links create the note), backlinks
  ("Linked Mentions"), `#tags`, checklists you can tick in the preview,
  renaming updates links in other notes
- Tags in the sidebar (from text and from "Tags…" on any note), full-text
  search, Today's Note (with today's planner tasks), text templates
  (built-in and "Save as Template"), and a Graph view of notes, links and
  tags: arrange it as a web, folder islands, a timeline, rings around a
  note, a tree, a grid or by hand (drag notes; places are kept), with
  dots, bubbles or cards colored by kind, folder or age, and straight,
  curved or dashed links
- Backup (the drive button at the top of the sidebar): "Back Up Library…"
  writes the whole library (notes, PDFs, pictures, recordings, folders,
  planner, expenses, mind maps, slides and study) into one ZIP file and
  lets you save it to iCloud Drive or anywhere in Files. "Restore from a
  Backup…" checks the file and shows what it holds (notes new to the
  library, newer in the backup, or the same), then offers: Add to My
  Library (adds what's missing and updates notes that are newer in the
  backup; nothing is removed), Choose Notes… (browse the backup and bring
  back only the notes you pick; ones you still have come back as copies),
  or Replace Library. Before any restore the library is kept on the iPad
  (the last three copies) so it can be undone. Automatic backups (every
  day or week, keeping the last few) are made on the iPad when InkPad
  opens; the backup button turns orange after two weeks without any
  backup. "Earlier Versions…" in a note's menu brings back an older
  version of that note from these backups, as a copy. AI keys stay in the keychain and are never in a backup

See [ROADMAP.md](ROADMAP.md) for the next phases.

> This code is written without access to Apple's iOS SDK, so each change is
> first compiled on the iPad. Please report any Swift Playgrounds error
> messages exactly.

## Run it on your iPad

Requirements: iPadOS 17 or later and the free **Swift Playgrounds** app
(App Store).

1. In Safari, open this repository on GitHub, tap **Code → Download ZIP**.
2. In the **Files** app, open *Downloads* and tap the ZIP to unzip it.
3. Open the unzipped folder and tap **InkPad.swiftpm**. It opens in Swift
   Playgrounds. (Alternatively, in Swift Playgrounds use **Open** / the
   folder icon and pick `InkPad.swiftpm`.)
4. Tap **Run** (▶). Use the full-screen button to work in the app.

To update later, download the ZIP again and open the new `InkPad.swiftpm`.
Your notes are not lost: they live in the app's own Documents folder.

## Project layout

```
InkPad.swiftpm/
  Package.swift     Swift Playgrounds app definition
  App/              App entry point
  Models/           Folders, notes, page templates, page geometry
  Storage/          LibraryStore: the only code that reads/writes files
  Rendering/        Paper templates, page background, thumbnails, PDF and
                    PowerPoint export
  Canvas/           PencilKit canvas and its SwiftUI bridge
  Audio/            Recording and playback
  Slides/           Reading notes and writing slide decks
  AI/               AI services, note text, study prompts
  Views/            Library, sidebar, notes grid, editor, study
```

## Data format

Stored under the app's `Documents/InkPad/`:

- `library.json` — folders and note summaries (`hiddenFromAI` and
  `aiOnDeviceOnly` are the AI Firewall levels); deleted notes are listed under `trash` (their folders stay
  in `notes/` until deleted for good)
- `notes/<id>/note.json` — template, paper color, page count, text boxes
- `notes/<id>/drawing.data` — PencilKit drawing
- `notes/<id>/document.pdf` — imported PDF (copied, never modified)
- `notes/<id>/images/` — images placed on pages
- `notes/<id>/note.md` — a text note's Markdown
- `notes/<id>/audio/` — audio recordings (`note.json` lists them with the
  moment each started, to match them with the writing), and
  `<file>.transcript.json` with each one's transcript and chapters
  (derived, safe to lose)
- `notes/<id>/thumbnail.png` — preview (regenerated on save)
- `notes/<id>/text.json` — handwriting and PDF text read with Vision
  (regenerated when needed; used by search and AI study)
- `workspace.json` — planner, expenses, mind maps, slide decks, flashcards,
  quizzes, and Flowmodoro tasks, sessions and the running timer
- `decks/<id>/` — page pictures used in slide decks

If `library.json` cannot be read, InkPad opens read-only instead of
overwriting it (restoring a backup still works).

A backup is a plain ZIP (files stored uncompressed): `backup.json` (format,
date, note and folder counts) and an `InkPad/` folder with the files above
exactly as they are. Copies kept before a restore are in
`Documents/InkPad Safety Copies/`.
