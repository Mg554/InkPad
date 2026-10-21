# InkPad

A free, private, Notability-style note-taking app for iPad, built as a
**Swift Playgrounds** app (SwiftUI + PencilKit). All notes stay on your iPad.

## Status

Done:

- Folders and notes library (create, rename, move, delete, title search)
- Handwriting canvas with Apple Pencil (PencilKit tool palette: pens,
  highlighter, eraser, lasso, ruler, colors)
- "Pencil only" mode: the pencil draws, fingers scroll and zoom
- Pinch-to-zoom, stacked pages, Add Page
- Page templates: blank, lined, grid, dotted
- Undo / redo, autosave, first-page thumbnails
- PDF import from Files, handwriting and highlighting on PDF pages, extra
  blank/lined/grid/dotted pages after the PDF
- Export any note as a PDF (Save to Files, AirDrop, Mail, ...)

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
- `notes/<id>/note.json` — page template and page count
- `notes/<id>/drawing.data` — PencilKit drawing
- `notes/<id>/document.pdf` — imported PDF (copied, never modified)
- `notes/<id>/thumbnail.png` — preview (regenerated on save)

If `library.json` cannot be read, InkPad opens read-only instead of
overwriting it.
