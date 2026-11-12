# InkPad

A free, private, Notability-style note-taking app for iPad, built as a
**Swift Playgrounds** app (SwiftUI + PencilKit). All notes stay on your iPad;
the optional AI study features send only the notes you study to the AI
service you choose, with your own API key.

## Status

Done:

- Library: nested folders with colors, notes grid with thumbnails, title
  search, quick actions (New Note, Import a File, Find a Template)
- Organizing: Favorites (sidebar) and pinned notes at the top of every
  list; sort by last edited, created, name, pages or a Custom Order you
  drag (kept per folder); grid or a detailed list (preview, folder, tags,
  pages, audio, edited; tap a column to sort); optional covers per note
  (color, gradient or pattern with the title in a font); Smart
  Collections that fill themselves (Recently Edited, PDFs, With Audio,
  Unfinished Tasks, Untitled) plus your own from rules (kind, tag, edited
  recently, audio, tasks, favorites)
- Pages: in the pages panel, Select several pages to move, duplicate or
  delete them; Move to Another Note… keeps the writing editable (ink,
  text boxes, images, PDF pages and sizes), at the start, the end or
  after a page, or copies them; Duplicate Page; named, colored page tabs
  shown on the page edge as a jump list; any page size per page (A4,
  Letter, A5, square, 16:9, iPad screen or custom in mm, portrait or
  landscape), and exported PDFs keep each page's size
- Writing: pen presets (a pen, color and width saved as a chip in the
  toolbar, + to save the current pen) and named color palettes (Classic,
  Study, Pastel, Earth, Neon, or your own) from the palette button next
  to the colors; Gestures (Customize Toolbar › Gestures) set what the
  Apple Pencil double tap and two- and three-finger taps do (undo, redo,
  switch tools, hide the toolbar, Reading Mode, ⌘K, add a sticky note,
  next or previous page); Reading Mode (⋯ menu) hides every tool and bar
  so nothing is written by accident
- Sticky notes (+ › Sticky Note): colored notes on the page with typed
  text and handwriting, a group name, folding to a small square; tap one
  with a finger to open it; turn it into a Planner task linked to its
  page (the task opens that page) or into a new page; ⋯ › Sticky Notes…
  lists them by group
- Stickers (+ › Stickers…): built-in packs (study labels, marks, emoji,
  arrows and shapes), your own from Photos or Files with the background
  cut out on the device, and handwriting saved from the lasso (Save as
  Sticker) that goes back as editable ink; folders, favorites and
  recently used
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
- Undo and redo at the start of the toolbar (also when it is collapsed),
  and finger shortcuts on the page: a two-finger tap undoes, a
  three-finger tap redoes, with a small label saying what happened
- Arabic or English: the AR/EN button at the top of the sidebar (or
  Appearance › Language) switches the whole interface at once, right to
  left in Arabic; pages, ink and your own notes are never changed
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
- Command Anywhere: ⌘K, the floating ⌘ button (drag it anywhere) or a
  three-finger swipe down opens a glass command palette. Type, write with
  the Pencil or speak (on the iPad, English or Arabic) to search notes
  (titles, text and handwriting), go anywhere (sections, folders, tags),
  create (note, text note, reminder, task, expense, mind map), run the
  open note's commands (study, slides, export, paper, rename, history,
  remind me) or change settings (themes, appearance, back up now,
  handwriting, Flowmodoro). Sentences such as "remind me to call Sara
  tomorrow at 9", "ذكرني بالمحاضرة غداً الساعة 9" or "coffee 15" are
  understood on the iPad; "Ask AI" sends only that sentence when it
  isn't. Shortcuts: ⌘N, ⌘⇧N, ⌘⇧R, ⌘⇧T, ⌘⇧E, ⌘⇧M, ⌘⇧B, ⌘⇧D, ⌘1–⌘8
- PDF Tools (sidebar, PDF24-style, all offline): merge PDFs, split a PDF
  by its chapters, every N pages or typed ranges, take pages out to a new
  note, remove pages, rotate pages; from the library or from Files.
  Convert: images to PDF (Photos or Files), scan with the camera into a
  searchable note, web page to PDF (the one tool that uses the
  internet), PDF to images, extract the pictures stored in a PDF.
  Protect & Edit: compress (with sizes before and after, optionally
  keeping text searchable), protect with a password (shared or saved to
  Files), unlock a locked PDF, redact words or drawn areas (redacted
  pages become pictures, so the text is really gone), watermark, page
  numbers, and sign (write a signature, choose page and place).
  Compare Editions: two editions of a book matched chapter by chapter
  (new, removed, changed with how much, same), the pages side by side
  with added words in green and removed words in red, the changed
  sentences, an AI explanation of what changed (AI Firewall), a report
  saved as a note, and bookmarks moved to the new edition.
  Results are new notes; originals never change
- PDF books: the book button opens Chapters & Bookmarks with the book's
  own outline (chapters and sections), colored bookmarks, reading
  progress and the current chapter. Any chapter becomes a mind map (its
  sections and key concepts, made on the iPad, or by AI when allowed by
  the AI Firewall), a concept graph (tap a concept to see and jump to the
  pages that mention it), or a note of its own. In More: Insert Pages from
  Another PDF (into the open note, after the current page) and Send Pages
  to a New Note
- Notebook beside the book: the book button's neighbour opens a lined
  notebook (a note of its own) next to the book, with a handle to make it
  wider. A page for each chapter (Start Notes), the notebook follows the
  chapter being read, every page remembers the book pages it was written
  beside (tap p. 12 to go there), and Lasso › Send to Notebook copies part
  of the book as a picture or as text, with its page number
- OCR for scanned books (on the iPad, English and Arabic): the book
  panel notices pages without text and Make Searchable gives them an
  invisible text layer, in the background, keeping your writing in
  place; then the whole book can be searched (Search tab), selected,
  highlighted and exported as a searchable PDF. PDF Tools › Make
  Searchable does the same for any PDF. Lasso any area (even a scan or a
  picture) › Text from Area reads it as text or as a table, to copy, put
  on the page, save as a text note, or Clean Up with AI (AI Firewall)
- AI with books (AI Firewall): Ask the Book (the Ask tab) finds the
  pages that match a question on the iPad and sends only those; answers
  cite pages you can tap to jump to, and can be saved as notes. Each
  chapter's menu adds Summary Notes, Flashcards, Exam Questions
  (board-exam style, like NBRC) and a Glossary note (terms, definitions,
  pages, #glossary)
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
- Planner × Flowmodoro: Focus on This (task menu, task editor, Today and
  Matrix) starts Flowmodoro on a planner task and logs the time on it;
  estimates vs. real time, with corrected suggestions once InkPad has
  learned how long your tasks take. Planner views: Today (hour timeline,
  focus done, reminders due, Plan My Day puts tasks into time blocks with
  breaks, hard tasks in your best focus hours), Board, List, Calendar,
  Eisenhower Matrix (drag between Do Now / Schedule / Delegate / Later)
  and Weekly Review (focus per day, tasks done, best hour, estimate
  accuracy, where the time went)
- Distraction Box: catch a stray thought while focusing, typed or written
  with the pen (read on the iPad), from Flowmodoro, the note toolbar, the
  sidebar or ⌘K; stats by hour and task; each one can become a reminder
- Focus Garden: a plant per subject (a planner task's first tag, or the
  Flowmodoro task) grows from seed to grand tree with focus time and
  dresses for the season. Smart breaks: review due flashcards, a guided
  breathing minute, or a tip to move. Study-linked tasks: link a task to a
  note or book chapter; finishing it plans reviews 1, 3 and 7 days later.
  Planner Timeline (Gantt) shows tasks as bars over four weeks
- Customize focus (paintbrush in Flowmodoro and the Planner): timer face
  (ring, big digits, analog, liquid, growing plant) with glow, Planner
  cards (glass, sticky notes, minimal, neon), background, ambient sound
  made on the iPad (rain, ocean, white, pink or brown noise, also on
  breaks) and the break chime
- Focus Mode, in a note or book (the scope button or ⌘K): the tools hide,
  a small bar shows the session timer, catch a distraction and End, and a
  study companion sits beside the page: related notes and concepts (on
  the iPad), two quick questions about the page (AI through the AI
  Firewall, or from your flashcards) and your weak cards on the subject.
  Ending shows a wrap-up: time, pages, strokes, distractions, and a
  spaced review to plan. Focus Mode also has its own calm screen (⌘K or
  Flowmodoro): pick a task, the timer face, a seasonal scene, sounds and
  your subject's plant growing
- Knowledge GPS (sidebar or ⌘K): a map of what you're learning — a PDF
  book by its chapters, a subject's tagged notes, or stations you make
  (an exam syllabus) — drawn as islands with a path and fog, a metro
  line, or a skill tree. Each station's progress comes from reading,
  flashcard memory, quizzes and focus time, and your own mark (started,
  understood, mastered). It shows where you are, the next stop, time
  left at your pace and before the exam, and a daily route you can add
  to the Planner (with a reroute when you fall behind)
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
