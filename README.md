# InkPad

A free, private, Notability-style note-taking app for iPad, built as a
**Swift Playgrounds** app (SwiftUI + PencilKit). All notes stay on your iPad.

## Status

Done:

- Library: nested folders with colors, notes grid with thumbnails, title
  search, quick actions (New Note, Import a File, Find a Template)
- Floating toolbar combining Notability and Apple Notes: quill, fountain
  pen, pen, monoline, pencil, crayon, watercolor, highlighter, eraser
  (pixel or whole stroke), text, lasso, insert
  menu, ruler, finger drawing; per-tool colors plus custom colors, three
  widths per tool with a fine-tuning slider; collapses to a small pill
- Apple Pencil double-tap switches to the eraser and back
- Text boxes: tap the page with the Text tool; bold, italic, underline,
  strikethrough, size, color, bulleted lists; move and resize
- Photos and images from Files placed on pages; move and resize
- Templates: Plain, Lined, Grid, Dot, Hexagonal Grid, Cornell Note,
  College Rule, Manuscript, Two and Three Column; six paper colors
- PDF import (one or several files), writing and highlighting on PDF pages
- Quick export, or "Export as..." with background paper, page margins,
  page range and password options
- Page sidebar with thumbnails (insert a blank page after any page, delete
  pages), page counter with previous/next
- Undo / redo for ink; autosave in the background

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
  Rendering/        Paper templates, tiled page background, thumbnails
  Canvas/           PencilKit canvas and its SwiftUI bridge
  Views/            Library, sidebar, notes grid, editor
```

## Data format

Stored under the app's `Documents/InkPad/`:

- `library.json` — folders and note summaries
- `notes/<id>/note.json` — template, paper color, page count, text boxes
- `notes/<id>/drawing.data` — PencilKit drawing
- `notes/<id>/document.pdf` — imported PDF (copied, never modified)
- `notes/<id>/images/` — images placed on pages
- `notes/<id>/thumbnail.png` — preview (regenerated on save)

If `library.json` cannot be read, InkPad opens read-only instead of
overwriting it.
