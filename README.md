# pura-tiff

A pure Ruby TIFF decoder/encoder with zero C extension dependencies.

Part of the **pura-*** series — pure Ruby image codec gems.

## Features

- TIFF decoding and encoding (uncompressed)
- Image resizing (bilinear / nearest-neighbor / fit / fill)
- No native extensions, no FFI, no external dependencies
- CLI tool included

## Installation

```bash
gem install pura-tiff
```

## Usage

```ruby
require "pura-tiff"

# Decode
image = Pura::Tiff.decode("photo.tiff")
image.width      #=> 400
image.height     #=> 400
image.pixels     #=> Raw RGB byte string
image.pixel_at(x, y) #=> [r, g, b]

# Encode
Pura::Tiff.encode(image, "output.tiff")

# Resize
thumb = image.resize(200, 200)
fitted = image.resize_fit(800, 600)
```

## CLI

```bash
pura-tiff decode input.tiff --info
pura-tiff resize input.tiff --width 200 --height 200 --out thumb.tiff
```

## Benchmark

400×400 image, Ruby 4.0.2 + YJIT.

### Decode

| Decoder | Time |
|---------|------|
| **pura-tiff** | **14 ms** |
| ffmpeg (C) | 59 ms |

**pura-tiff is 4× faster than ffmpeg** for TIFF decoding. No other pure Ruby TIFF implementation exists.

### Encode

| Encoder | Time | Notes |
|---------|------|-------|
| **pura-tiff** | **0.6 ms** | Uncompressed |

## Why pure Ruby?

- **`gem install` and go** — no `brew install`, no `apt install`, no C compiler needed
- **4× faster than C** — uncompressed TIFF is pure data copying, and Ruby + YJIT handles it beautifully
- **Works everywhere Ruby works** — CRuby, ruby.wasm, JRuby, TruffleRuby
- **Part of pura-\*** — convert between JPEG, PNG, BMP, GIF, TIFF, WebP seamlessly

## Related gems

| Gem | Format | Status |
|-----|--------|--------|
| [pura-jpeg](https://github.com/komagata/pura-jpeg) | JPEG | ✅ Available |
| [pura-png](https://github.com/komagata/pura-png) | PNG | ✅ Available |
| [pura-bmp](https://github.com/komagata/pura-bmp) | BMP | ✅ Available |
| [pura-gif](https://github.com/komagata/pura-gif) | GIF | ✅ Available |
| **pura-tiff** | TIFF | ✅ Available |
| [pura-ico](https://github.com/komagata/pura-ico) | ICO | ✅ Available |
| [pura-webp](https://github.com/komagata/pura-webp) | WebP | ✅ Available |
| [pura-image](https://github.com/komagata/pura-image) | All formats | ✅ Available |

## License

MIT
