# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pura-tiff"

class TestDecoder < Minitest::Test
  FIXTURE_DIR = File.join(__dir__, "fixtures")

  def setup
    generate_fixtures unless File.exist?(File.join(FIXTURE_DIR, "rgb_uncompressed.tiff"))
  end

  def test_decode_rgb_uncompressed
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "rgb_uncompressed.tiff"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    assert_equal 4 * 4 * 3, image.pixels.bytesize
    # Top-left pixel should be red
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
  end

  def test_decode_rgb_colors
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "rgb_uncompressed.tiff"))
    # Row 1: green
    r, g, b = image.pixel_at(0, 1)
    assert_equal 0, r
    assert_equal 255, g
    assert_equal 0, b
    # Row 2: blue
    r, g, b = image.pixel_at(0, 2)
    assert_equal 0, r
    assert_equal 0, g
    assert_equal 255, b
    # Row 3: white
    r, g, b = image.pixel_at(0, 3)
    assert_equal 255, r
    assert_equal 255, g
    assert_equal 255, b
  end

  def test_decode_grayscale
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "gray_uncompressed.tiff"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    r, g, b = image.pixel_at(0, 0)
    assert_equal 128, r
    assert_equal 128, g
    assert_equal 128, b
  end

  def test_decode_palette
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "palette.tiff"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    # Index 0 = red
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
    # Index 1 = green
    r, g, b = image.pixel_at(0, 1)
    assert_equal 0, r
    assert_equal 255, g
    assert_equal 0, b
  end

  def test_decode_packbits
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "rgb_packbits.tiff"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
  end

  def test_decode_lzw
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "rgb_lzw.tiff"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
  end

  def test_decode_from_binary_data
    data = File.binread(File.join(FIXTURE_DIR, "rgb_uncompressed.tiff"))
    image = Pura::Tiff.decode(data)
    assert_equal 4, image.width
    assert_equal 4, image.height
  end

  def test_decode_big_endian
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "rgb_big_endian.tiff"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
  end

  def test_decode_min_is_white
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "gray_min_white.tiff"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    # Original value 0 -> inverted to 255
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 255, g
    assert_equal 255, b
  end

  def test_pixel_at_out_of_bounds
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "rgb_uncompressed.tiff"))
    assert_raises(IndexError) { image.pixel_at(-1, 0) }
    assert_raises(IndexError) { image.pixel_at(0, -1) }
    assert_raises(IndexError) { image.pixel_at(4, 0) }
    assert_raises(IndexError) { image.pixel_at(0, 4) }
  end

  def test_to_rgb_array
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "rgb_uncompressed.tiff"))
    arr = image.to_rgb_array
    assert_equal 16, arr.size
    assert_equal [255, 0, 0], arr[0]
  end

  def test_to_ppm
    image = Pura::Tiff.decode(File.join(FIXTURE_DIR, "rgb_uncompressed.tiff"))
    ppm = image.to_ppm
    assert ppm.start_with?("P6\n4 4\n255\n".b)
    assert_equal "P6\n4 4\n255\n".bytesize + (4 * 4 * 3), ppm.bytesize
  end

  def test_invalid_data
    assert_raises(Pura::Tiff::DecodeError) { Pura::Tiff.decode("not a tiff".b) }
  end

  private

  def generate_fixtures
    FileUtils.mkdir_p(FIXTURE_DIR)

    generate_rgb_uncompressed
    generate_grayscale_uncompressed
    generate_palette
    generate_rgb_packbits
    generate_rgb_lzw
    generate_rgb_big_endian
    generate_gray_min_white
  end

  # Helper to build a minimal TIFF file (little-endian)
  def build_tiff(tags, pixel_data, big_endian: false)
    out = String.new(encoding: Encoding::BINARY)

    pack_u16 = big_endian ? "n" : "v"
    pack_u32 = big_endian ? "N" : "V"

    num_tags = tags.size
    ifd_offset = 8
    ifd_size = 2 + (num_tags * 12) + 4

    # Calculate overflow
    overflow_offset = ifd_offset + ifd_size
    overflow = String.new(encoding: Encoding::BINARY)

    tag_entries = tags.sort_by { |t| t[:id] }.map do |tag|
      value_bytes = tag_value_bytes(tag, pack_u16, pack_u32)
      if value_bytes.bytesize > 4
        vo = overflow_offset + overflow.bytesize
        overflow << value_bytes
        { tag: tag, value_offset: vo }
      else
        { tag: tag, inline: value_bytes }
      end
    end

    pixel_offset = overflow_offset + overflow.bytesize

    # Patch strip offsets
    tag_entries.each do |e|
      next unless e[:tag][:id] == 273

      e[:tag][:values] = [pixel_offset]
      vb = tag_value_bytes(e[:tag], pack_u16, pack_u32)
      if vb.bytesize <= 4
        e[:inline] = vb
        e.delete(:value_offset)
      end
    end

    # Header
    out << (big_endian ? "MM" : "II")
    out << [42].pack(pack_u16)
    out << [ifd_offset].pack(pack_u32)

    # IFD
    out << [num_tags].pack(pack_u16)
    tag_entries.each do |e|
      tag = e[:tag]
      out << [tag[:id]].pack(pack_u16)
      out << [tag[:type]].pack(pack_u16)
      out << [tag[:count]].pack(pack_u32)

      if e[:value_offset]
        out << [e[:value_offset]].pack(pack_u32)
      else
        vb = e[:inline] || tag_value_bytes(tag, pack_u16, pack_u32)
        vb += ("\x00" * [4 - vb.bytesize, 0].max)
        out << vb.byteslice(0, 4)
      end
    end
    out << [0].pack(pack_u32)

    out << overflow
    out << pixel_data

    out
  end

  def tag_value_bytes(tag, pack_u16, pack_u32)
    data = String.new(encoding: Encoding::BINARY)
    case tag[:type]
    when 3 # SHORT
      tag[:values].each { |v| data << [v].pack(pack_u16) }
    when 4 # LONG
      tag[:values].each { |v| data << [v].pack(pack_u32) }
    when 5 # RATIONAL
      i = 0
      while i < tag[:values].size
        data << [tag[:values][i]].pack(pack_u32)
        data << [tag[:values][i + 1]].pack(pack_u32)
        i += 2
      end
    when 1 # BYTE
      tag[:values].each { |v| data << [v].pack("C") }
    end
    data
  end

  def make_tags(width, height, compression, photometric, samples_per_pixel, bits_per_sample, strip_byte_count,
                extra_tags: [])
    [
      { id: 256, type: 4, count: 1, values: [width] },            # ImageWidth
      { id: 257, type: 4, count: 1, values: [height] },           # ImageLength
      { id: 258, type: 3, count: bits_per_sample.size, values: bits_per_sample }, # BitsPerSample
      { id: 259, type: 3, count: 1, values: [compression] },      # Compression
      { id: 262, type: 3, count: 1, values: [photometric] },      # Photometric
      { id: 273, type: 4, count: 1, values: [0] },                # StripOffsets (patched)
      { id: 277, type: 3, count: 1, values: [samples_per_pixel] }, # SamplesPerPixel
      { id: 278, type: 4, count: 1, values: [height] },           # RowsPerStrip
      { id: 279, type: 4, count: 1, values: [strip_byte_count] }, # StripByteCounts
      { id: 282, type: 5, count: 1, values: [72, 1] },            # XResolution
      { id: 283, type: 5, count: 1, values: [72, 1] },            # YResolution
      { id: 296, type: 3, count: 1, values: [2] } # ResolutionUnit
    ] + extra_tags
  end

  def generate_rgb_uncompressed
    width = 4
    height = 4
    pixels = String.new(encoding: Encoding::BINARY)
    4.times { pixels << [255, 0, 0].pack("C3") }    # red
    4.times { pixels << [0, 255, 0].pack("C3") }    # green
    4.times { pixels << [0, 0, 255].pack("C3") }    # blue
    4.times { pixels << [255, 255, 255].pack("C3") } # white

    tags = make_tags(width, height, 1, 2, 3, [8, 8, 8], pixels.bytesize)
    File.binwrite(File.join(FIXTURE_DIR, "rgb_uncompressed.tiff"), build_tiff(tags, pixels))
  end

  def generate_grayscale_uncompressed
    width = 4
    height = 4
    pixels = ([128].pack("C") * (width * height))

    tags = make_tags(width, height, 1, 1, 1, [8], pixels.bytesize)
    File.binwrite(File.join(FIXTURE_DIR, "gray_uncompressed.tiff"), build_tiff(tags, pixels))
  end

  def generate_palette
    width = 4
    height = 4
    pixels = String.new(encoding: Encoding::BINARY)
    4.times { pixels << [0].pack("C") }  # red
    4.times { pixels << [1].pack("C") }  # green
    4.times { pixels << [2].pack("C") }  # blue
    4.times { pixels << [3].pack("C") }  # white

    # TIFF ColorMap: 256 reds, 256 greens, 256 blues (16-bit values)
    color_map = Array.new(256 * 3, 0)
    # Reds
    color_map[0] = 65_535   # index 0 red
    color_map[3] = 65_535   # index 3 white
    # Greens
    color_map[256 + 1] = 65_535  # index 1 green
    color_map[256 + 3] = 65_535  # index 3 white
    # Blues
    color_map[512 + 2] = 65_535  # index 2 blue
    color_map[512 + 3] = 65_535  # index 3 white

    color_map_tag = { id: 320, type: 3, count: 256 * 3, values: color_map }
    tags = make_tags(width, height, 1, 3, 1, [8], pixels.bytesize, extra_tags: [color_map_tag])
    File.binwrite(File.join(FIXTURE_DIR, "palette.tiff"), build_tiff(tags, pixels))
  end

  def generate_rgb_packbits
    width = 4
    height = 4
    pixels = String.new(encoding: Encoding::BINARY)
    4.times { pixels << [255, 0, 0].pack("C3") }
    4.times { pixels << [0, 255, 0].pack("C3") }
    4.times { pixels << [0, 0, 255].pack("C3") }
    4.times { pixels << [255, 255, 255].pack("C3") }

    compressed = compress_packbits(pixels)
    tags = make_tags(width, height, 32_773, 2, 3, [8, 8, 8], compressed.bytesize)
    File.binwrite(File.join(FIXTURE_DIR, "rgb_packbits.tiff"), build_tiff(tags, compressed))
  end

  def generate_rgb_lzw
    width = 4
    height = 4
    pixels = String.new(encoding: Encoding::BINARY)
    4.times { pixels << [255, 0, 0].pack("C3") }
    4.times { pixels << [0, 255, 0].pack("C3") }
    4.times { pixels << [0, 0, 255].pack("C3") }
    4.times { pixels << [255, 255, 255].pack("C3") }

    compressed = compress_lzw(pixels)
    tags = make_tags(width, height, 5, 2, 3, [8, 8, 8], compressed.bytesize)
    File.binwrite(File.join(FIXTURE_DIR, "rgb_lzw.tiff"), build_tiff(tags, compressed))
  end

  def generate_rgb_big_endian
    width = 4
    height = 4
    pixels = String.new(encoding: Encoding::BINARY)
    4.times { pixels << [255, 0, 0].pack("C3") }
    4.times { pixels << [0, 255, 0].pack("C3") }
    4.times { pixels << [0, 0, 255].pack("C3") }
    4.times { pixels << [255, 255, 255].pack("C3") }

    tags = make_tags(width, height, 1, 2, 3, [8, 8, 8], pixels.bytesize)
    File.binwrite(File.join(FIXTURE_DIR, "rgb_big_endian.tiff"), build_tiff(tags, pixels, big_endian: true))
  end

  def generate_gray_min_white
    width = 4
    height = 4
    # All zeros -> after MinIsWhite inversion, should become 255
    pixels = ([0].pack("C") * (width * height))

    tags = make_tags(width, height, 1, 0, 1, [8], pixels.bytesize)
    File.binwrite(File.join(FIXTURE_DIR, "gray_min_white.tiff"), build_tiff(tags, pixels))
  end

  def compress_packbits(data)
    out = String.new(encoding: Encoding::BINARY)
    pos = 0
    size = data.bytesize

    while pos < size
      remaining = size - pos
      if remaining == 1
        out << [0].pack("c") # literal run of 1
        out << data.byteslice(pos, 1)
        pos += 1
      else
        # Check for a run
        run_byte = data.getbyte(pos)
        run_len = 1
        run_len += 1 while run_len < 128 && pos + run_len < size && data.getbyte(pos + run_len) == run_byte

        if run_len >= 2
          out << [257 - run_len].pack("C")
          out << run_byte.chr
          pos += run_len
        else
          # Literal run
          lit_len = 1
          while lit_len < 128 && pos + lit_len < size
            break if pos + lit_len + 1 < size && data.getbyte(pos + lit_len) == data.getbyte(pos + lit_len + 1)

            lit_len += 1
          end
          out << [lit_len - 1].pack("C")
          out << data.byteslice(pos, lit_len)
          pos += lit_len
        end
      end
    end

    out
  end

  def compress_lzw(data)
    # TIFF LZW: MSB-first bit packing
    clear_code = 256
    eoi_code = 257

    # Initialize table
    table = {}
    256.times { |i| table[i.chr.b] = i }
    next_code = 258
    code_size = 9
    max_code = 512

    out_bits = []

    # Emit clear code first
    out_bits << [clear_code, code_size]

    w = "".b
    data.each_byte do |byte|
      wc = w + byte.chr.b
      if table.key?(wc)
        w = wc
      else
        out_bits << [table[w], code_size]
        if next_code < 4096
          table[wc] = next_code
          next_code += 1
          if next_code > max_code && code_size < 12
            code_size += 1
            max_code <<= 1
          end
        end
        w = byte.chr.b
      end
    end

    out_bits << [table[w], code_size] unless w.empty?
    out_bits << [eoi_code, code_size]

    # Pack bits MSB-first
    out = String.new(encoding: Encoding::BINARY)
    bit_buf = 0
    bits_in_buf = 0

    out_bits.each do |code, size|
      bit_buf = (bit_buf << size) | code
      bits_in_buf += size

      while bits_in_buf >= 8
        bits_in_buf -= 8
        out << ((bit_buf >> bits_in_buf) & 0xFF).chr
      end
    end

    # Flush remaining bits
    out << ((bit_buf << (8 - bits_in_buf)) & 0xFF).chr if bits_in_buf.positive?

    out
  end
end
