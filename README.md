# pura-tiff

A pure Ruby TIFF decoder/encoder without additional image-processing libraries.

Part of the **pura-*** series — pure Ruby image codec gems.

## Features

- TIFF decoding and encoding (uncompressed)
- Image resizing (bilinear / nearest-neighbor / fit / fill)
- No image-specific native extension or FFI dependency
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

These historical measurements include ffmpeg process startup. They do not compare against an in-process C codec or establish Rails pipeline throughput.

400×400 image, Ruby 4.0.2 + YJIT.

### Decode

| Decoder | Time |
|---------|------|
| **pura-tiff** | **14 ms** |
| ffmpeg (C) | 59 ms |


### Encode

| Encoder | Time | vs ffmpeg | Notes |
|---------|------|-----------|-------|
| **pura-tiff** | **0.8 ms** | **0.01× — 73× faster than ffmpeg!** | Uncompressed |
| ffmpeg (C) | 58 ms | — | |

## Why pure Ruby?

- **`gem install` and go** — no `brew install`, no `apt install`, no C compiler needed
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

## Pixel model and limitations

Images contain 8-bit RGB pixels. Only the first IFD is decoded. Supported input is 8-bit strip data with uncompressed, LZW, or PackBits compression; encoding is uncompressed. Alpha and extra samples are discarded.

`crop(x, y, width, height)` requires integer coordinates, positive dimensions, and a region entirely inside the image; invalid regions raise `ArgumentError`.

## Decode limits

`Pura::Tiff.decode(input, max_input_bytes: 64 * 1024 * 1024,
max_pixels: 40_000_000, max_decoded_bytes: 256 * 1024 * 1024)` accepts a path or binary data.
All limits must be positive integers. These defaults bound input, pixel count, and decoded data size; they are not a cap on the Ruby process's total memory or CPU time.

Invalid image data raises `Pura::Tiff::DecodeError`; exceeding a configured limit raises its subclass `Pura::Tiff::LimitExceeded`.
TIFF decoding validates directory/tag bounds and rejects truncated or oversized strip output.

## License

MIT
