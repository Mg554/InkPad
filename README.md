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
  interactive category chart, currency and optional decimals; Mind Maps
  with curved glowing branches, drag, pinch-zoom and one-tap tidy layout
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
  and name the notes they come from), flashcards with spaced review ("N
  flashcards ready for review"), multiple-choice quizzes, Smart Notes
  (organized study notes saved as a text note) and slides, for all notes
  or the ones you select. Works with Claude (Anthropic), ChatGPT (OpenAI),
  Gemini, OpenRouter, Groq, DeepSeek, Mistral, any OpenAI-compatible
  service, or Apple Intelligence on the iPad. Set it up in Study with AI ›
  AI Settings: pick the service, paste your API key (kept in the iPad's
  keychain) and tap Test Connection
- Handwriting search: handwritten and PDF notes are read with Vision after
  you edit them, and the library search finds their words
- Rotating the iPad keeps the page steady, with the same part of the page
  in the middle
- Lasso (Notability-style): circle ink, drag it, and use Style (size 1-20,
  solid/dashed/dotted, colors), Duplicate, Cut, Copy, Paste and Delete
- Text boxes: tap the page with the Text tool; bold, italic, underline,
  strikethrough, size, color, bulleted lists; move and resize. Type with
  the keyboard (it opens even when you tap with Apple Pencil), or switch to
  "Write with Pencil" (in the toolbar or the keyboard's shortcut bar) to
  handwrite and have it turned into text
- Appearance: Match iPad, Light or Dark (the circle button at the top of
  the sidebar); pages keep their paper color
- Flowmodoro (from the Pythonation/flowmodoro-wep-app web app): a task
  list; tap a task to start the work stopwatch, stop when your focus fades
  and you earn a break of 5% of the work time (at least a minute; 10, 15
  or 20% can be chosen), with a sound and a notification when it ends.
  Edit, complete, reorder and delete tasks, and see every session in the
  history with today's total focus time
- Photos and images from Files placed on pages; move and resize
- Templates: Plain, Lined, Grid, Dot, Hexagonal Grid, Cornell Note,
  College Rule, Manuscript, Two and Three Column; six paper colors
- PDF import (one or several files), writing and highlighting on PDF pages
- Quick export, or "Export as..." with background paper, page margins,
  page range and password options
- Page sidebar with thumbnails (insert a blank page after any page, delete
  pages), page counter with previous/next
- Undo / redo for ink; autosave in the background
- Obsidian-style text notes: Markdown with live highlighting, edit/split/
  preview, `[[links]]` (unresolved links create the note), backlinks
  ("Linked Mentions"), `#tags`, checklists you can tick in the preview,
  renaming updates links in other notes
- Tags in the sidebar (from text and from "Tags…" on any note), full-text
  search, Today's Note (with today's planner tasks), text templates
  (built-in and "Save as Template"), and a Graph view of notes, links and
  tags

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

- `library.json` — folders and note summaries
- `notes/<id>/note.json` — template, paper color, page count, text boxes
- `notes/<id>/drawing.data` — PencilKit drawing
- `notes/<id>/document.pdf` — imported PDF (copied, never modified)
- `notes/<id>/images/` — images placed on pages
- `notes/<id>/note.md` — a text note's Markdown
- `notes/<id>/audio/` — audio recordings (`note.json` lists them with the
  moment each started, to match them with the writing)
- `notes/<id>/thumbnail.png` — preview (regenerated on save)
- `notes/<id>/text.json` — handwriting and PDF text read with Vision
  (regenerated when needed; used by search and AI study)
- `workspace.json` — planner, expenses, mind maps, slide decks, flashcards,
  quizzes, and Flowmodoro tasks, sessions and the running timer
- `decks/<id>/` — page pictures used in slide decks

If `library.json` cannot be read, InkPad opens read-only instead of
overwriting it.
