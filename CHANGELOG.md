# Changelog

All notable changes to AmigaIconWriter. This project aims to follow
[Keep a Changelog](https://keepachangelog.com/) and Semantic Versioning.

## [Unreleased]

### Added
- **`.info` decoder** (`IconDecoder`) — the inverse of `IconWriter`: parses the
  `DiskObject`/`Gadget` header, planar `Image`(s), `DrawerData`,
  `DefaultTool`/`ToolTypes`, and the trailing `FORM ICON` GlowIcon. Powers
  round-trip tests and an accurate preview.
- **Accurate "Amiga-truth" preview** in the app — encodes then decodes the real
  bytes, so the canvas shows the reduced GlowIcon palette and the low-colour
  planar fallback, not the full-colour source.
- **Open/edit existing icons** — app *Import .info* (re-edit an icon and
  re-export) and a cross-platform `amigaicon inspect <file.info>` (decode-only,
  runs on Linux too).
- **Workbench pen palettes** (`WorkbenchPalette`) selectable by release —
  WB 1.x (4), WB 2.x/3.1 (4), WB 3.2 (8/16), MagicWB (8/16) — with the leading
  system pens **reserved** during colour reduction.
- **Custom palette editor** — edit exact pen RGBs, add/remove reserved pens, set
  total colours; custom pens persist per icon in the project.
- **Floyd–Steinberg dithering** and **alpha-weighted area-averaging downscale**
  for the planar reduction (`--dither`, `--resample`).
- **Non-square canvases** via `--preserve-aspect` (canvas hugs the artwork).
- **DrawerData** written/parsed for disk and drawer icons (window position/size
  + scroll offset).
- **Badges/emblems** — multiple per icon, composited from the kit's `blending`
  primitive, positioned/resized by direct drag on a canvas (normalised, saved
  with the project).
- **Effects & adjustments** (kit primitives, wired through options/app/CLI):
  - **Outline** — solid silhouette stroke.
  - **Shadows** — any number of outer and/or inner shadows, each with offset,
    colour, opacity and a feathered **blur**.
  - **Posterize**, **box blur**, flat **tint**, and **orientation** (flip H/V,
    90° rotation).
- **Forward-compatible document decoding** — older `.amigaicons` projects keep
  opening as settings fields are added (tolerant `init(from:)`).
- **`IconWriter.reencode`** — losslessly rewrite a decoded icon (edit metadata
  or reduced images without re-quantising source art).
- **Batch/folder image import** and **default-tool / tool-types editing** in the
  app.
- **NewIcons decoder** + round-trip test.
- **CI** (`.github/workflows/ci.yml`): Linux (`swift test`) and macOS
  (`swift build`/`test` + `xcodebuild` of the app scheme).

### Changed
- **Isolated the core**: `AmigaIconKit` is now pure Foundation with zero platform
  dependencies; the Apple-only ImageIO loading moved to a separate
  `AmigaIconImageIO` product. The whole package builds on Linux.
- Colour reduction picks the smaller of RLE vs raw per stream.

### Fixed
- **16-bit ColorIcon overflow**: the per-image byte-count fields were silently
  clamped, which could corrupt large icons; now bounded and validated, with a
  descriptive `ColorIconError`.
- **`CGRect.isFinite`** misuse in the app's CoreImage path (the app never
  compiled before).
- **NewIcons UTF-8 corruption**: payload bytes > 0x7F were mangled; now Latin-1.
- Cross-module access slips caught by the macOS CI (`effected`, `maxPens`).
