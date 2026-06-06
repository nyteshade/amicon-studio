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

> On Linux the `amigaicon` CLI and the SwiftUI app won't build (they need
> ImageIO / SwiftUI), but `AmigaIconKit` and its tests do. To run only the kit
> tests on Linux, temporarily trim `Package.swift` to the `AmigaIconKit` library
> and test target.

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
- **Leading sidebar** — *tools*: a palette of CoreImage effects (brightness,
  contrast, saturation, hue, sepia, monochrome, invert, bloom, sharpen,
  vignette) you can stack onto the artwork, plus *Output Settings* (icon type,
  GlowIcon canvas/artwork sizes, max colours, glow colour & radius, planar
  size & palette).
- Effects are applied **non-destructively**: the project keeps the **original
  dropped images at full resolution**, so you can change target sizes or
  effects at any time and re-render without quality loss (CandyBar-style).
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

## Format references

- `struct DiskObject` / `Gadget` / `Image` — *Amiga ROM Kernel Reference
  Manual: Libraries*, `workbench/workbench.h`, `intuition/intuition.h`.
- ColorIcon `FACE`/`IMAG` chunks and the bit-stream RLE — icon.library
  (OS 3.5+) autodocs.

## License

MIT.
