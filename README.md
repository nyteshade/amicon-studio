# AmigaIconWriter

A macOS app (and supporting Swift library + CLI) for authoring **Amiga `.info`
icons** from modern macOS image formats — including 24-bit **GlowIcons**
(ColorIcons) supported by AmigaOS 3.5+/3.2, with the characteristic glow on the
clicked (selected) state.

> Status: the **core format library is implemented and unit-tested**
> (planar `.info` + ColorIcon/GlowIcon round-trips verified). The SwiftUI app
> builds and runs on macOS. **NewIcons** support is **experimental** — see the
> caveat below.

---

## What it writes

Every `.info` produced contains, in one file:

| Layer | Format | Read by | Notes |
|-------|--------|---------|-------|
| **Classic planar** | `DiskObject` + `Gadget` + bitplane `Image`(s) | OS 1.x–3.x and everything newer | Always written as the universal fallback. Small canvas, few colours (Workbench / MagicWB palette), as was typical pre-GlowIcons. |
| **GlowIcon / ColorIcon** | trailing IFF `FORM ICON` (`FACE` + `IMAG`×1–2) | icon.library on OS 3.5+ (and the OS 3.2 update) | 24-bit RGB palette (up to 256 colours), transparent-index, RLE-compressed. The "modern" icon. 48×48 artwork centred in a 54×54 canvas by default, leaving room for the glow. |
| **NewIcons** *(experimental)* | encoded into the icon's tool types | the NewIcons patch / PowerIcons on OS 3.x | Off by default. See caveat. |

Old systems ignore the trailing `FORM ICON` and render the planar image; OS 3.5+
prefers the ColorIcon. One file works everywhere.

### The clicked-state glow

Amiga icons have two visual states: **normal** (unclicked) and **selected**
(clicked). For GlowIcons the selected state classically gets a coloured glow
around the artwork. AmigaIconWriter can either use a second image you supply, or
**auto-generate** the glow from the normal artwork (a distance-transform bloom
in the canvas margin), with configurable colour and radius.

### Workbench palettes (planar colour reduction)

Classic `.info` files store **no palette of their own** — the planar image's
indices are drawn with the live Workbench screen pens — so the planar fallback
is reduced against a chosen target pen set (`WorkbenchPalette`):

| Preset | Pens | Notes |
|--------|------|-------|
| Workbench 1.x | 4 | blue / white / black / orange |
| Workbench 2.x / 3.1 | 4 | the grey desktop default |
| Workbench 3.2 | 8 or 16 | first 8 pens reserved (MagicWB-compatible) |
| MagicWB | 8 or 16 | the de-facto 8-pen standard |

For the 8- and 16-colour sets the **leading system pens are reserved** (kept
exactly, so the icon never clobbers the desktop pens); on a 16-colour set the
upper 8 pens are generated from the artwork during reduction. Pick the set in
the CLI with `--palette` (`wb1`/`wb2`/`wb32-8`/`wb32-16`/`mwb8`/`mwb16`) or in
the app's *Output Settings*.

The app's **palette editor** (in *Output Settings*) lets you start from a preset
and then tweak the exact pen RGBs, add/remove reserved pens, and set the total
colour count — handy if you target a specific release's prefs. Any edit becomes
a **Custom** palette whose pens are saved with the project, per icon.

Reduction quality is controlled by two more knobs (both on by default):
**scaling** uses alpha-weighted area-averaging when shrinking photos to icon
size (`--resample smooth|nearest`), and the planar reduction uses
**Floyd–Steinberg dithering** so photos read well at 4–16 pens
(`--dither fs|none`). Pixel-art sources usually want `nearest` + `none`.

By default the canvas is square; pass `--preserve-aspect` (or toggle it in
*Output Settings*) to emit a **non-square** canvas that hugs the artwork's
aspect ratio — as many classic icons do — keeping a uniform glow margin on all
sides.

> ⚠️ The exact RGB values for the WB 1.x / 2.x pens and the OS 3.2 system pens
> are the conventional/MagicWB-compatible ones; tweak them in
> `WorkbenchPalettes.swift` / `ClassicIcon.swift` if you target a specific
> release's prefs exactly.

---

## Project layout

```
Package.swift                 SwiftPM: library + CLI + app targets
Sources/
  AmigaIconKit/               Pure-Foundation core — zero platform deps, tested.
                              The reusable library: everything that creates,
                              encodes and decodes .info icons lives here.
    BinaryWriter.swift          big-endian byte reader/writer + bit reader/writer
    RGBAImage.swift             pixel buffer + glow generator
    IndexedImage.swift          median-cut quantiser + indexed -> RGBA renderer
    ClassicIcon.swift           DiskObject types, planar bitplane Image, palettes
    ColorIcon.swift             IFF FORM ICON (GlowIcon) encoder
    PackBits.swift              ColorIcon bit-stream RLE (+ decoder)
    NewIcons.swift              EXPERIMENTAL NewIcons tool-type encoder
    IconComposer.swift          fit/centre artwork in a canvas
    IconWriter.swift            high-level .info assembler + IconOptions
    IconDecoder.swift           reads .info back (round-trip / preview / editing)
  AmigaIconImageIO/           Optional Apple-only convenience target.
    ImageLoading.swift          NSImage/ImageIO <-> RGBAImage (PNG/JPEG/HEIC…)
  amigaicon/                  Command-line front-end (macOS)
  AmigaIconWriterApp/         SwiftUI document app (macOS)
Tests/AmigaIconKitTests/      XCTest round-trip + structure tests
Apps/Info.plist               document-type plist for the Xcode app target
```

---

## Building & testing the core (any platform with Swift)

The kit and tests are pure Foundation and build on macOS **and Linux**:

```bash
swift test                       # runs the format round-trip / structure tests
```

> The whole package builds on Linux: `AmigaIconKit` and its tests build fully,
> and the `amigaicon` **`inspect`** subcommand (decode only, no image I/O) runs
> everywhere. Only the *writing* side of the CLI needs ImageIO; on Linux it
> prints a "requires macOS" notice, and the SwiftUI app compiles to a trivial
> stub. So plain `swift build` / `swift test` work as-is — no manifest trimming.
>
> ```bash
> amigaicon inspect MyTool.info   # dump type, sizes, palette, tool types (any OS)
> ```
>
> CI (`.github/workflows/ci.yml`) runs the suite on Linux and additionally
> builds **every** target (incl. the SwiftUI app) on a macOS runner, which is
> what type-checks the macOS/SwiftUI code.

### Reusing the core in your own code

`AmigaIconKit` is a standalone, dependency-free library product — the entire
create / encode / decode pipeline with no platform requirements. Depend on it
directly (`.product(name: "AmigaIconKit", package: "AmigaIconWriter")`) and feed
it an `RGBAImage`:

```swift
import AmigaIconKit

var art = RGBAImage(width: 64, height: 64)   // fill your pixels…
let bytes = try IconWriter.build(normal: art, selected: nil, options: IconOptions())
// …write `bytes` to "Foo.info". Read it back with IconDecoder.decode(bytes).
```

On Apple platforms, add the separate **`AmigaIconImageIO`** product if you want
to load source art from files (`RGBAImage(contentsOf:)`) or get `pngData()`.

## The command-line tool (macOS)

```bash
swift run amigaicon --normal artwork.png --out MyTool.info
swift run amigaicon --normal app.png --selected app-pressed.png --type tool
swift run amigaicon --normal folder.png --type drawer --glow-color 3B8BFF
amigaicon --help                 # full option list
```

By default it writes both the planar fallback and a 24-bit GlowIcon, and
auto-generates the glow for the clicked state when you don't pass `--selected`.

## Building the macOS app

The app is a standard SwiftUI document app. Two ways to build it:

**A. Quick run via SwiftPM** (no bundle, fine for trying it out):

```bash
swift run AmigaIconWriterApp
```

**B. Proper `.app` in Xcode** (recommended — gives you the document type,
sandboxing, and a distributable bundle):

1. In Xcode: *File ▸ New ▸ Project… ▸ macOS ▸ App*, SwiftUI lifecycle.
2. Delete the template's `ContentView`/`App` files.
3. Add this package as a local Swift Package dependency (*File ▸ Add Package
   Dependencies… ▸ Add Local…*) and link the **AmigaIconKit** product.
4. Add the Swift files from `Sources/AmigaIconWriterApp/` to the app target.
5. Set the target's **Info.plist** to `Apps/Info.plist` (or merge its
   `CFBundleDocumentTypes` / `UTExportedTypeDeclarations` entries) so `.amigaicons`
   project files are registered.

### Using the app

- **Bottom strip** — every icon in the project, each shown in a macOS-style
  *squircle tile*. The squircle is just the container chrome; the Amiga artwork
  inside keeps its own shape and transparency (it is **not** clipped to a
  squircle). Click to select; `+` adds a new icon.
- **Centre canvas** — two large slots for the selected icon: **left =
  unclicked**, **right = clicked**. Drag any macOS image (PNG, JPEG, TIFF,
  HEIC…) onto a slot, from Finder or another app.
- **Badges** — drop one or more emblem images onto the badge canvas, then
  **drag to position** and **drag the corner handle to resize** each one. They're
  composited onto the artwork and stored (normalised) with the project.
- **Leading sidebar** — *tools*: a palette of CoreImage effects (brightness,
  contrast, saturation, hue, sepia, monochrome, invert, bloom, sharpen,
  vignette) you can stack onto the artwork, plus *Output Settings* (icon type,
  GlowIcon canvas/artwork sizes, max colours, glow colour & radius, planar
  size & palette, dithering & scaling, and the **default tool / tool types**).
- Effects are applied **non-destructively**: the project keeps the **original
  dropped images at full resolution**, so you can change target sizes or
  effects at any time and re-render without quality loss (CandyBar-style).
- **Import Images** (toolbar): add one or many source images — or a whole
  **folder** of them — as new icons in a single step (CandyBar-style sets).
- **Import** (toolbar): open existing `.info` icons back into the project — the
  GlowIcon (or planar fallback) becomes an editable original, with the icon type,
  default tool and tool types carried over — then tweak and re-export.
- **Export** (toolbar): write the selected icon — or every icon in the project
  — to `.info` files.

---

## ⚠️ NewIcons is experimental

NewIcons was never officially documented. The encoder in `NewIcons.swift`
follows the commonly-cited structure (7-bit printable transfer encoding, header
+ palette + run-length-packed indices in the tool types) but its exact byte
layout has **not** been verified against a real Workbench. It is **off by
default**. If you enable it, test the result on real hardware or an emulator
(WinUAE/FS-UAE with the NewIcons patch) and expect to adjust the header packing
/ RLE in that one isolated file. The Classic planar and GlowIcon paths are
**not** experimental and are covered by tests.

The codec is now at least **self-consistent**: `NewIcons.decode` reverses
`encode`, and a round-trip test proves an opaque image survives the header,
Latin-1 transfer encoding, palette and RLE intact. (The transparent-pen index
is still a best guess, and none of it is verified against a real Workbench.)

## Format references

- `struct DiskObject` / `Gadget` / `Image` — *Amiga ROM Kernel Reference
  Manual: Libraries*, `workbench/workbench.h`, `intuition/intuition.h`.
- ColorIcon `FACE`/`IMAG` chunks and the bit-stream RLE — icon.library
  (OS 3.5+) autodocs.

## License

MIT.
