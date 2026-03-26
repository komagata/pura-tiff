# frozen_string_literal: true

require_relative "lib/pura/tiff/version"

Gem::Specification.new do |spec|
  spec.name = "pura-tiff"
  spec.version = Pura::Tiff::VERSION
  spec.authors = ["komagata"]
  spec.summary = "Pure Ruby TIFF decoder/encoder"
  spec.description = "A pure Ruby TIFF decoder and encoder with zero C extension dependencies. " \
                     "Supports uncompressed, LZW, and PackBits compression, RGB, grayscale, and palette color."
  spec.homepage = "https://github.com/komagata/pure-tiff"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir["lib/**/*.rb", "bin/*", "LICENSE", "README.md"]
  spec.bindir = "bin"
  spec.executables = ["pure-tiff"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
