# WriteBench icon

Original four-stroke W, refined for a native Mac application. The mark keeps the blue/periwinkle identity requested by the user; no stock image, external font or raster logo is used.

- A 1024-unit vector grid, optically centred mark, consistent 23° stroke angles and a softly shaped pale porcelain tile.
- Restrained overlap shadows and one lighting direction. Highlights are omitted and strokes slightly strengthened at 16/32 px.
- Independently rendered 16, 32, 64, 128, 256, 512 and 1024 px PNGs with transparency and sRGB colour conversion, compiled through Xcode's macOS AppIcon asset catalog.
- Editable `WriteBench.svg` master with named layers; complete `.icns` and 1024 px exports.
- The dark export is a separate brand asset, not a claim of automatic macOS appearance switching. This release uses the light icon in its bundle.
- Prior artwork is preserved in `Previous/`. `WriteBench-icon-preview.png` compares old/refined/dark artwork and native small sizes.

Generate from the project root:

```sh
swift scripts/make-icon.swift
swift scripts/icon-preview.swift
iconutil -c icns Design/Icon/Exports/WriteBench.iconset -o Design/Icon/Exports/WriteBench.icns
```

The app icon itself uses the normal Xcode asset pipeline. An Icon Composer document is not part of this release; no first-run license agreement was accepted on the user's behalf. The vector master can later be imported as layers into Icon Composer.
