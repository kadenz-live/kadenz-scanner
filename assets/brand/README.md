# Brand assets

All vector assets derive from the Kadenz brand geometry — the **"Solid"
ticket mark** (plate 335×210, side notches, punch hole, nine waveform bars +
two dashes as the perforation line) and the constructed **`kadenz.`**
wordmark (monoline, round caps, zero font dependency). The parametric
generator lives in the Kadenz monorepo at
`docs/brand/generate_brand_assets.py`; regenerate with:

```sh
python3 generate_brand_assets.py --scanner assets/brand
rsvg-convert -w 1024 assets/brand/wordmark.svg -o assets/brand/wordmark.png
rsvg-convert -w 960  assets/brand/splash_logo.svg -o assets/brand/splash_logo.png
```

## Files

- `mark.svg` — canonical Solid ticket mark (violet), viewBox 400×260.
- `wordmark.svg` / `wordmark.png` — white stacked lockup (mark above
  `kadenz.`); rendered by the Flutter splash screen at 280 pt width on the
  brand-violet canvas.
- `splash_logo.svg` / `splash_logo.png` — white mark on a transparent square,
  padded so it survives the Android 12 circular splash-icon mask; consumed by
  `flutter_native_splash` (`dart run flutter_native_splash:create`).
- `icon_source.svg` — flat vector fallback tile (violet + white mark). The
  shipping launcher icon `icon_1024.png` is the noir ticket artwork and is
  intentionally **not** generated from this file.
