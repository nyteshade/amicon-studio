# Manual test checklist

Items that CI can't verify — macOS-only UI (it only **compiles** there via the
`xcodebuild` job) and on-device Amiga rendering. Kit logic is covered by the unit
tests (`swift test`); this list is everything else. Grown as features land.

## Build / project
- [ ] App builds & runs for **My Mac** (not an iOS destination).
- [ ] New project, add/delete icons, bottom strip selection.
- [ ] Save → reopen a `.amigaicons` project round-trips (all settings/layers/effects).
- [ ] Undo/redo (⌘Z / ⇧⌘Z): restores prior states; image edits included; sane
      granularity; no spurious or doubled steps.

## Import / export
- [ ] Import Images (multi-select **and** a folder of images).
- [ ] Import `.info` (re-edit an existing icon; type/default-tool/tool-types carried).
- [ ] Export `.info` (selected), Export All (folder), Export PNG (composite).
- [ ] Drag-drop an image onto the Unclicked / Clicked wells.
- [ ] `amigaicon inspect file.info` output looks right (also builds on Linux).

## Canvas / layers (Photoshop-style)
- [ ] Drag a layer to move it; handle aligns with where it composites.
- [ ] Corner-handle resize feels right.
- [ ] Shift-drag constrains layer movement to one axis.
- [ ] **Scroll-wheel** over canvas resizes the selected layer — **check direction/sign** (easy to flip).
- [ ] Context menu on a layer (canvas + list): Hide/Show, Duplicate, Bring to
      Front/Forward, Send Backward/to Back, Blend submenu, Applies-To submenu, Delete.
- [ ] Context menu on empty canvas: Add Layer / Deselect.
- [ ] Layer list: visibility toggles, reorder arrows, selection highlight.
- [ ] Double-click a layer name (or Rename in the menu) to rename inline.
- [ ] Inspector: name, opacity, size, blend, target, visibility — live-update preview.
- [ ] Blend modes look correct (multiply/screen/overlay/darken/lighten/add).
- [ ] Drop an image onto the layer canvas to add a layer.

## Effects
- [ ] CoreImage effect stack: add/adjust each; live preview on both states.
- [ ] Per-effect **target** (Both/Unclicked/Clicked) applies to the right state.
- [ ] "Show original (bypass filters)" toggle = before/after.

## Output settings
- [ ] Palette editor: edit pen RGBs, add/remove pens, total colours; preset picker.
- [ ] Shadows: add/remove, kind (outer/inner), X/Y, colour, opacity, blur.
- [ ] Outline (thickness/colour), orientation (flip/rotate), blur, tint, posterize
      all reflect in the preview.
- [ ] Planar fallback preview is crisp and matches the chosen palette.
- [ ] Default tool / tool types editing.

## On real hardware / emulator (deep authenticity)
- [ ] Exported `.info` renders on AmigaOS 3.5+/3.2 (GlowIcon) and OS1–3 (planar).
- [ ] Reserved Workbench pens look right; verify exact RGBs per release.
- [ ] Drawer/disk icons open a window (DrawerData) as expected.
- [ ] NewIcons output (experimental) on a real Workbench with the NewIcons patch.
