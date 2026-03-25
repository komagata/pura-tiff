# frozen_string_literal: true

require_relative "../lib/pura-tiff"

module DecodeBenchmark
  def self.run(input)
    unless File.exist?(input)
      puts "Generating test image with ffmpeg..."
      unless generate_test_image(input)
        $stderr.puts "Error: could not generate test image. Provide an existing TIFF file."
        exit 1
      end
    end

    file_size = File.size(input)
    puts "Benchmark: decoding #{input} (#{file_size} bytes)"
    puts "=" * 60

    results = []

    # pura-tiff
    results << bench("pura-tiff") do
      image = Pura::Tiff.decode(input)
      image.pixels.bytesize
    end

    # ffmpeg
    results << bench("ffmpeg") do
      out = `ffmpeg -v quiet -i #{shell_escape(input)} -f rawvideo -pix_fmt rgb24 pipe:1 2>/dev/null`
      $?.success? ? out.bytesize : nil
    end

    # ImageMagick
    if command_exists?("magick")
      results << bench("imagemagick") do
        out = `magick #{shell_escape(input)} -depth 8 rgb:- 2>/dev/null`
        $?.success? ? out.bytesize : nil
      end
    end

    # Print results table
    puts
    puts format("%-15s %12s %15s %s", "Decoder", "Time (ms)", "Output (bytes)", "Status")
    puts "-" * 60
    results.each do |r|
      time_str = r[:time] ? format("%.2f", r[:time] * 1000) : "N/A"
      size_str = r[:output_size] ? r[:output_size].to_s : "N/A"
      status = r[:note] || "ok"
      puts format("%-15s %12s %15s %s", r[:name], time_str, size_str, status)
    end

    # Memory usage
    puts
    puts "Memory usage (current process): #{memory_usage_kb} KB"
  end

  def self.bench(name)
    GC.start
    start_mem = memory_usage_kb
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output_size = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end_mem = memory_usage_kb

    if output_size
      { name: name, time: elapsed, output_size: output_size, mem_delta: end_mem - start_mem }
    else
      { name: name, time: nil, output_size: nil, note: "failed" }
    end
  rescue => e
    { name: name, time: nil, output_size: nil, note: "error: #{e.message}" }
  end

  def self.generate_test_image(path)
    return false unless command_exists?("ffmpeg")
    system(
      "ffmpeg", "-v", "quiet", "-y",
      "-f", "lavfi", "-i", "testsrc=duration=0.04:size=640x480:rate=1",
      "-frames:v", "1",
      path
    )
    $?.success?
  end

  def self.memory_usage_kb
    if RUBY_PLATFORM =~ /darwin/
      `ps -o rss= -p #{$$}`.strip.to_i
    elsif File.exist?("/proc/#{$$}/status")
      File.read("/proc/#{$$}/status")[/VmRSS:\s+(\d+)/, 1].to_i
    else
      0
    end
  end

  def self.command_exists?(cmd)
    system("which #{cmd} > /dev/null 2>&1")
  end

  def self.shell_escape(s)
    "'" + s.gsub("'", "'\\''") + "'"
  end
end
