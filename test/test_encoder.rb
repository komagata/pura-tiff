# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pura-tiff"

class TestEncoder < Minitest::Test
  FIXTURE_DIR = File.join(__dir__, "fixtures")

  def test_encode_creates_valid_tiff
    image = Pura::Tiff::Image.new(4, 4, "\xFF\x00\x00".b * 16)
    path = File.join(FIXTURE_DIR, "enc_test.tiff")
    Pura::Tiff.encode(image, path)
    data = File.binread(path)
    # Check TIFF header (little-endian)
    assert_equal "II", data[0, 2]
    assert_equal 42, data[2, 2].unpack1("v")
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_roundtrip
    pixels = String.new(encoding: Encoding::BINARY)
    4.times { pixels << ("\xFF\x00\x00".b * 4) } # red row
    image = Pura::Tiff::Image.new(4, 4, pixels)
    path = File.join(FIXTURE_DIR, "enc_roundtrip.tiff")
    Pura::Tiff.encode(image, path)
    decoded = Pura::Tiff.decode(path)
    assert_equal 4, decoded.width
    assert_equal 4, decoded.height
    assert_equal image.pixels, decoded.pixels
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_solid_colors
    [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255], [0, 0, 0]].each do |r, g, b|
      pixel = [r, g, b].pack("CCC")
      pixels = pixel * 16
      image = Pura::Tiff::Image.new(4, 4, pixels)
      path = File.join(FIXTURE_DIR, "enc_solid.tiff")
      Pura::Tiff.encode(image, path)
      decoded = Pura::Tiff.decode(path)
      dr, dg, db = decoded.pixel_at(0, 0)
      assert_equal r, dr
      assert_equal g, dg
      assert_equal b, db
      File.delete(path)
    end
  end

  def test_various_sizes
    [[1, 1], [3, 5], [100, 1], [1, 100], [64, 64]].each do |w, h|
      pixels = ([128, 64, 32].pack("CCC") * (w * h))
      image = Pura::Tiff::Image.new(w, h, pixels)
      path = File.join(FIXTURE_DIR, "enc_size.tiff")
      Pura::Tiff.encode(image, path)
      decoded = Pura::Tiff.decode(path)
      assert_equal w, decoded.width
      assert_equal h, decoded.height
      assert_equal pixels, decoded.pixels
      File.delete(path)
    end
  end

  def test_pixel_data_preserved_exactly
    pixels = String.new(encoding: Encoding::BINARY)
    16.times do |i|
      pixels << [i * 16, 255 - (i * 16), i * 8].pack("CCC")
    end
    image = Pura::Tiff::Image.new(4, 4, pixels)
    path = File.join(FIXTURE_DIR, "enc_exact.tiff")
    Pura::Tiff.encode(image, path)
    decoded = Pura::Tiff.decode(path)
    assert_equal pixels, decoded.pixels
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_encode_returns_byte_count
    image = Pura::Tiff::Image.new(2, 2, "\xFF\x00\x00".b * 4)
    path = File.join(FIXTURE_DIR, "enc_count.tiff")
    bytes = Pura::Tiff.encode(image, path)
    assert_equal File.size(path), bytes
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
