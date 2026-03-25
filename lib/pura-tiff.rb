# frozen_string_literal: true

require_relative "pura/tiff/version"
require_relative "pura/tiff/image"
require_relative "pura/tiff/decoder"
require_relative "pura/tiff/encoder"

module Pura
  module Tiff
    def self.decode(input)
      Decoder.decode(input)
    end

    def self.encode(image, output_path)
      Encoder.encode(image, output_path)
    end
  end
end
