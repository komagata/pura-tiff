# frozen_string_literal: true

module Pura
  module Tiff
    class Encoder
      def self.encode(image, output_path)
        data = new(image).encode
        File.binwrite(output_path, data)
        data.bytesize
      end

      def initialize(image)
        @image = image
        @width = image.width
        @height = image.height
        @pixels = image.pixels
      end

      def encode
        out = String.new(encoding: Encoding::BINARY)

        # We'll build: header (8) + IFD + tag data + pixel data
        # Layout:
        #   0..7:     header
        #   8..N:     IFD (2 + num_tags*12 + 4 bytes for next IFD pointer)
        #   N+1..M:   tag value data that doesn't fit in 4 bytes
        #   M+1..end: pixel data (strips)

        pixel_data = @pixels
        strip_byte_count = pixel_data.bytesize

        # Tags we'll write (sorted by tag ID as required by TIFF spec)
        tags = []
        # ImageWidth (256)
        tags << make_tag(256, TYPE_LONG, 1, [@width])
        # ImageLength (257)
        tags << make_tag(257, TYPE_LONG, 1, [@height])
        # BitsPerSample (258) - 3 values: 8, 8, 8
        tags << make_tag(258, TYPE_SHORT, 3, [8, 8, 8])
        # Compression (259) - None
        tags << make_tag(259, TYPE_SHORT, 1, [1])
        # PhotometricInterpretation (262) - RGB
        tags << make_tag(262, TYPE_SHORT, 1, [2])
        # StripOffsets (273) - will be patched
        tags << make_tag(273, TYPE_LONG, 1, [0])
        # SamplesPerPixel (277)
        tags << make_tag(277, TYPE_SHORT, 1, [3])
        # RowsPerStrip (278) - all rows in one strip
        tags << make_tag(278, TYPE_LONG, 1, [@height])
        # StripByteCounts (279)
        tags << make_tag(279, TYPE_LONG, 1, [strip_byte_count])
        # XResolution (282)
        tags << make_tag(282, TYPE_RATIONAL, 1, [72, 1])
        # YResolution (283)
        tags << make_tag(283, TYPE_RATIONAL, 1, [72, 1])
        # ResolutionUnit (296) - inches
        tags << make_tag(296, TYPE_SHORT, 1, [2])

        tags.sort_by! { |t| t[:id] }

        num_tags = tags.size
        ifd_offset = 8
        ifd_size = 2 + (num_tags * 12) + 4 # count + entries + next IFD pointer

        # Calculate overflow data offset (for values > 4 bytes)
        overflow_offset = ifd_offset + ifd_size
        overflow_data = String.new(encoding: Encoding::BINARY)

        # Assign offsets for overflow values
        tags.each do |tag|
          value_bytes = tag_value_bytes(tag)
          if value_bytes.bytesize > 4
            tag[:value_offset] = overflow_offset + overflow_data.bytesize
            overflow_data << value_bytes
          else
            tag[:value_offset] = nil # fits inline
          end
        end

        # Pixel data offset
        pixel_offset = overflow_offset + overflow_data.bytesize

        # Patch StripOffsets to point to pixel data
        strip_tag = tags.find { |t| t[:id] == 273 }
        strip_tag[:values] = [pixel_offset]

        # Write header (little-endian)
        out << "II" # Little-endian
        out << [42].pack("v")               # Magic
        out << [ifd_offset].pack("V")       # IFD offset

        # Write IFD
        out << [num_tags].pack("v")

        tags.each do |tag|
          out << [tag[:id]].pack("v")
          out << [tag[:type]].pack("v")
          out << [tag[:count]].pack("V")

          value_bytes = tag_value_bytes(tag)
          if value_bytes.bytesize > 4
            out << [tag[:value_offset]].pack("V")
          else
            # Pad to 4 bytes
            padded = value_bytes + ("\x00".b * (4 - value_bytes.bytesize))
            out << padded
          end
        end

        # Next IFD offset (0 = no more IFDs)
        out << [0].pack("V")

        # Write overflow data
        out << overflow_data

        # Write pixel data
        out << pixel_data

        out
      end

      private

      TYPE_SHORT    = 3
      TYPE_LONG     = 4
      TYPE_RATIONAL = 5

      def make_tag(id, type, count, values)
        { id: id, type: type, count: count, values: values }
      end

      def tag_value_bytes(tag)
        data = String.new(encoding: Encoding::BINARY)
        case tag[:type]
        when TYPE_SHORT
          tag[:values].each { |v| data << [v].pack("v") }
        when TYPE_LONG
          tag[:values].each { |v| data << [v].pack("V") }
        when TYPE_RATIONAL
          # values are [num, den] pairs flattened
          i = 0
          while i < tag[:values].size
            data << [tag[:values][i]].pack("V")
            data << [tag[:values][i + 1]].pack("V")
            i += 2
          end
        end
        data
      end
    end
  end
end
