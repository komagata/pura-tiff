# frozen_string_literal: true

module Pura
  module Tiff
    class DecodeError < StandardError; end

    class Decoder
      # TIFF tag IDs
      TAG_IMAGE_WIDTH           = 256
      TAG_IMAGE_LENGTH          = 257
      TAG_BITS_PER_SAMPLE       = 258
      TAG_COMPRESSION           = 259
      TAG_PHOTOMETRIC           = 262
      TAG_STRIP_OFFSETS         = 273
      TAG_SAMPLES_PER_PIXEL     = 277
      TAG_ROWS_PER_STRIP        = 278
      TAG_STRIP_BYTE_COUNTS     = 279
      TAG_X_RESOLUTION          = 282
      TAG_Y_RESOLUTION          = 283
      TAG_RESOLUTION_UNIT       = 296
      TAG_COLOR_MAP             = 320
      TAG_EXTRA_SAMPLES         = 338
      TAG_SAMPLE_FORMAT         = 339

      # Compression types
      COMPRESSION_NONE     = 1
      COMPRESSION_LZW      = 5
      COMPRESSION_PACKBITS = 32_773

      # Photometric interpretation
      PHOTO_MIN_IS_WHITE = 0
      PHOTO_MIN_IS_BLACK = 1
      PHOTO_RGB          = 2
      PHOTO_PALETTE      = 3

      # TIFF field types
      TYPE_BYTE      = 1
      TYPE_ASCII     = 2
      TYPE_SHORT     = 3
      TYPE_LONG      = 4
      TYPE_RATIONAL  = 5

      TYPE_SIZES = {
        TYPE_BYTE => 1,
        TYPE_ASCII => 1,
        TYPE_SHORT => 2,
        TYPE_LONG => 4,
        TYPE_RATIONAL => 8
      }.freeze

      def self.decode(input)
        data = if input.is_a?(String) && input.bytesize < 4096 && !input.include?("\0") && File.exist?(input)
                 File.binread(input)
               else
                 input.b
               end
        new(data).decode
      end

      def initialize(data)
        @data = data
        @pos = 0
        @little = true
      end

      def decode
        parse_header
        tags = parse_ifd(@ifd_offset)

        width = get_tag_value(tags, TAG_IMAGE_WIDTH) or raise DecodeError, "missing ImageWidth tag"
        height = get_tag_value(tags, TAG_IMAGE_LENGTH) or raise DecodeError, "missing ImageLength tag"
        compression = get_tag_value(tags, TAG_COMPRESSION) || COMPRESSION_NONE
        photometric = get_tag_value(tags, TAG_PHOTOMETRIC) || PHOTO_MIN_IS_BLACK
        samples_per_pixel = get_tag_value(tags, TAG_SAMPLES_PER_PIXEL) || 1
        bits_per_sample = get_tag_values(tags, TAG_BITS_PER_SAMPLE) || [8]
        get_tag_value(tags, TAG_ROWS_PER_STRIP) || height
        strip_offsets = get_tag_values(tags, TAG_STRIP_OFFSETS) or raise DecodeError, "missing StripOffsets tag"
        strip_byte_counts = get_tag_values(tags,
                                           TAG_STRIP_BYTE_COUNTS) or raise DecodeError, "missing StripByteCounts tag"
        color_map = get_tag_values(tags, TAG_COLOR_MAP)
        extra_samples = get_tag_values(tags, TAG_EXTRA_SAMPLES)

        unless bits_per_sample.all? { |b| b == 8 }
          raise DecodeError, "only 8-bit samples supported, got #{bits_per_sample.inspect}"
        end

        unless [COMPRESSION_NONE, COMPRESSION_LZW, COMPRESSION_PACKBITS].include?(compression)
          raise DecodeError, "unsupported compression: #{compression}"
        end

        # Decompress all strips
        raw = String.new(encoding: Encoding::BINARY)
        strip_offsets.each_with_index do |offset, i|
          count = strip_byte_counts[i]
          strip_data = @data.byteslice(offset, count)
          raise DecodeError, "truncated strip data" unless strip_data && strip_data.bytesize == count

          case compression
          when COMPRESSION_NONE
            raw << strip_data
          when COMPRESSION_LZW
            raw << decompress_lzw(strip_data)
          when COMPRESSION_PACKBITS
            raw << decompress_packbits(strip_data)
          end
        end

        # Convert to RGB
        pixels = convert_to_rgb(raw, width, height, photometric, samples_per_pixel, color_map, extra_samples)
        Image.new(width, height, pixels)
      end

      private

      def parse_header
        raise DecodeError, "data too short for TIFF header" if @data.bytesize < 8

        byte_order = @data.byteslice(0, 2)
        case byte_order
        when "II"
          @little = true
        when "MM"
          @little = false
        else
          raise DecodeError, "invalid byte order: #{byte_order.inspect}"
        end

        magic = read_u16(2)
        raise DecodeError, "invalid TIFF magic: #{magic}" unless magic == 42

        @ifd_offset = read_u32(4)
      end

      def parse_ifd(offset)
        count = read_u16(offset)
        tags = {}

        count.times do |i|
          entry_offset = offset + 2 + (i * 12)
          tag_id = read_u16(entry_offset)
          type = read_u16(entry_offset + 2)
          value_count = read_u32(entry_offset + 4)
          value_offset_field = entry_offset + 8

          type_size = TYPE_SIZES[type] || 1
          total_size = type_size * value_count

          data_offset = if total_size <= 4
                          value_offset_field
                        else
                          read_u32(value_offset_field)
                        end

          tags[tag_id] = { type: type, count: value_count, offset: data_offset }
        end

        tags
      end

      def get_tag_value(tags, tag_id)
        entry = tags[tag_id]
        return nil unless entry

        read_tag_value(entry, 0)
      end

      def get_tag_values(tags, tag_id)
        entry = tags[tag_id]
        return nil unless entry

        Array.new(entry[:count]) { |i| read_tag_value(entry, i) }
      end

      def read_tag_value(entry, index)
        offset = entry[:offset]
        case entry[:type]
        when TYPE_BYTE
          @data.getbyte(offset + index)
        when TYPE_SHORT
          read_u16(offset + (index * 2))
        when TYPE_LONG
          read_u32(offset + (index * 4))
        when TYPE_RATIONAL
          num = read_u32(offset + (index * 8))
          den = read_u32(offset + (index * 8) + 4)
          den.zero? ? 0 : num.to_f / den
        when TYPE_ASCII
          @data.getbyte(offset + index)
        else
          read_u32(offset + (index * 4))
        end
      end

      def read_u16(offset)
        if @little
          @data.getbyte(offset) | (@data.getbyte(offset + 1) << 8)
        else
          (@data.getbyte(offset) << 8) | @data.getbyte(offset + 1)
        end
      end

      def read_u32(offset)
        if @little
          @data.getbyte(offset) |
            (@data.getbyte(offset + 1) << 8) |
            (@data.getbyte(offset + 2) << 16) |
            (@data.getbyte(offset + 3) << 24)
        else
          (@data.getbyte(offset) << 24) |
            (@data.getbyte(offset + 1) << 16) |
            (@data.getbyte(offset + 2) << 8) |
            @data.getbyte(offset + 3)
        end
      end

      def convert_to_rgb(raw, width, height, photometric, samples_per_pixel, color_map, _extra_samples)
        pixel_count = width * height
        out = String.new(encoding: Encoding::BINARY, capacity: pixel_count * 3)

        case photometric
        when PHOTO_RGB
          if samples_per_pixel == 3
            # Direct RGB
            out << if raw.bytesize >= pixel_count * 3
                     raw.byteslice(0, pixel_count * 3)
                   else
                     raw
                   end
          elsif samples_per_pixel >= 4
            # RGBA or RGB + extra samples - strip extra channels
            pixel_count.times do |i|
              src = i * samples_per_pixel
              out << raw.byteslice(src, 3)
            end
          end

        when PHOTO_MIN_IS_BLACK
          if samples_per_pixel == 1
            # Grayscale
            pixel_count.times do |i|
              g = raw.getbyte(i)
              out << g.chr << g.chr << g.chr
            end
          elsif samples_per_pixel == 2
            # Grayscale + alpha - strip alpha
            pixel_count.times do |i|
              g = raw.getbyte(i * 2)
              out << g.chr << g.chr << g.chr
            end
          end

        when PHOTO_MIN_IS_WHITE
          if samples_per_pixel == 1
            pixel_count.times do |i|
              g = 255 - raw.getbyte(i)
              out << g.chr << g.chr << g.chr
            end
          elsif samples_per_pixel == 2
            pixel_count.times do |i|
              g = 255 - raw.getbyte(i * 2)
              out << g.chr << g.chr << g.chr
            end
          end

        when PHOTO_PALETTE
          raise DecodeError, "palette image missing ColorMap" unless color_map

          palette_size = color_map.size / 3
          pixel_count.times do |i|
            idx = raw.getbyte(i)
            # TIFF palette is stored as all reds, then all greens, then all blues
            # Values are 16-bit, scale to 8-bit
            r = color_map[idx] >> 8
            g = color_map[idx + palette_size] >> 8
            b = color_map[idx + (palette_size * 2)] >> 8
            out << r.chr << g.chr << b.chr
          end

        else
          raise DecodeError, "unsupported photometric interpretation: #{photometric}"
        end

        out
      end

      def decompress_lzw(data)
        # TIFF LZW uses big-endian bit packing (MSB first)
        out = String.new(encoding: Encoding::BINARY)
        bit_buf = 0
        bits_in_buf = 0
        pos = 0
        data_size = data.bytesize

        clear_code = 256
        eoi_code = 257
        next_code = 258
        code_size = 9
        max_code = 512

        # Table: array of strings
        table = Array.new(258) { |i| i < 256 ? i.chr.b : "".b }

        prev_string = nil

        loop do
          # Read code_size bits (MSB first for TIFF LZW)
          while bits_in_buf < code_size && pos < data_size
            bit_buf = (bit_buf << 8) | data.getbyte(pos)
            pos += 1
            bits_in_buf += 8
          end

          break if bits_in_buf < code_size

          code = (bit_buf >> (bits_in_buf - code_size)) & ((1 << code_size) - 1)
          bits_in_buf -= code_size

          if code == clear_code
            # Reset
            table = Array.new(258) { |i| i < 256 ? i.chr.b : "".b }
            next_code = 258
            code_size = 9
            max_code = 512
            prev_string = nil
            next
          end

          break if code == eoi_code

          if code < next_code
            current = table[code]
          elsif code == next_code && prev_string
            current = prev_string + prev_string[0]
          else
            raise DecodeError, "invalid LZW code: #{code} (next=#{next_code})"
          end

          out << current

          if prev_string && (next_code < 4096)
            table[next_code] = prev_string + current[0]
            next_code += 1

            if next_code > max_code - 1 && code_size < 12
              code_size += 1
              max_code <<= 1
            end
          end

          prev_string = current
        end

        out
      end

      def decompress_packbits(data)
        out = String.new(encoding: Encoding::BINARY)
        pos = 0
        size = data.bytesize

        while pos < size
          n = data.getbyte(pos)
          pos += 1

          if n < 128
            # Copy next n+1 bytes literally
            count = n + 1
            out << data.byteslice(pos, count)
            pos += count
          elsif n > 128
            # Repeat next byte (257-n) times
            count = 257 - n
            byte = data.byteslice(pos, 1)
            pos += 1
            out << (byte * count)
          end
          # n == 128: no-op
        end

        out
      end
    end
  end
end
