# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pura-tiff"

class TestInvalidData < Minitest::Test
  def test_rejects_out_of_bounds_ifd_offset
    data = "II".b + [42, 100].pack("vV")
    error = assert_raises(Pura::Tiff::DecodeError) { Pura::Tiff.decode(data) }
    assert_match(/bounds|truncated/, error.message)
  end

  def test_rejects_out_of_bounds_tag_values_before_allocating
    data = tiff
    # ImageWidth: replace the count with an impossible array size.
    data[14, 4] = [1_000_000].pack("V")
    error = assert_raises(Pura::Tiff::DecodeError) { Pura::Tiff.decode(data) }
    assert_match(/bounds|truncated/, error.message)
  end

  def test_checks_input_and_pixel_limits
    [[{ max_input_bytes: 8 }, /input limit/], [{ max_pixels: 1 }, /pixel limit/],
     [{ max_decoded_bytes: 1 }, /decoded byte limit/]].each do |options, message|
      error = assert_raises(Pura::Tiff::DecodeError) { Pura::Tiff.decode(tiff(width: 2), **options) }
      assert_match message, error.message
    end
  end

  def test_rejects_excess_packbits_output
    # The image is one RGB pixel, but the strip expands to 128 bytes.
    error = assert_raises(Pura::Tiff::DecodeError) do
      Pura::Tiff.decode(tiff(compression: 32_773, pixels: [129, 255].pack("C*")))
    end
    assert_match(/strip.*size/, error.message)
  end

  def test_rejects_truncated_packbits_literals
    error = assert_raises(Pura::Tiff::DecodeError) do
      Pura::Tiff.decode(tiff(compression: 32_773, pixels: [2, 255].pack("C*")))
    end
    assert_match(/truncated/, error.message)
  end

  def test_rejects_excess_uncompressed_strip_data
    error = assert_raises(Pura::Tiff::DecodeError) { Pura::Tiff.decode(tiff(pixels: "\0" * 6)) }
    assert_match(/strip.*size/, error.message)
  end

  private

  def tiff(width: 1, compression: 1, pixels: "\xFF\0\0".b)
    tags = [[256, 4, width], [257, 4, 1], [258, 3, 8], [259, 3, compression], [262, 3, 2],
            [273, 4, 122], [277, 3, 3], [278, 4, 1], [279, 4, pixels.bytesize]]
    entries = tags.map { |id, type, value| [id, type, 1, value].pack("vvVV") }.join
    "II".b + [42, 8, tags.size].pack("vVv") + entries + [0].pack("V") + pixels
  end
end
