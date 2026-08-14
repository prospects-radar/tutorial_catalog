# frozen_string_literal: true

require "json"

module TutorialCatalog
  # Reads the publish manifest — the only answer to "does this play, and from
  # where".
  #
  # Unlike the curriculum, this file changes under a running process: a publish
  # step rsyncs onto a live mount. So it is re-read whenever its mtime or size
  # moves, in every environment.
  #
  # Absent means zero watchable videos. That is the normal state in CI, in a
  # fresh checkout, and on a host that has never had a video uploaded, so it is
  # announced once at most and never raised.
  #
  # Malformed is treated as absent and deliberately *not* remembered, so the next
  # read tries again. A truncated file is an ordinary artifact of writing over a
  # live mount: briefly showing a landing video as planned beats a 500 on every
  # page that has a help menu.
  class Manifest
    Stat = Struct.new(:mtime, :size)

    def initialize(path, on_absent: nil)
      @path = path
      @on_absent = on_absent
      @mutex = Mutex.new
      reset
    end

    # { "slug" => { "en" => { "url" => ..., "duration" => 170 } } }
    def videos
      @mutex.synchronize do
        current = stat
        next @videos if @loaded && current == @loaded_stat

        parsed = parse(current)
        if parsed
          @videos = parsed
          @loaded_stat = current
          @loaded = true
        else
          @videos = {}
          @loaded = false
        end
        @videos
      end
    end

    def entry(slug, locale) = videos.dig(slug.to_s, locale.to_s)

    def slugs = videos.keys

    def reload!
      @mutex.synchronize { reset }
      self
    end

    private

    def reset
      @videos = {}
      @loaded = false
      @loaded_stat = nil
      @announced_absent = false
    end

    def stat
      return nil unless @path && File.exist?(@path)

      Stat.new(File.mtime(@path), File.size(@path))
    end

    # Returns the videos hash, or nil when the file could not be read — which is
    # the signal not to remember this outcome.
    def parse(current)
      return absent if current.nil?

      document = JSON.parse(File.read(@path))
      videos = document["videos"]
      videos.is_a?(Hash) ? videos.freeze : {}.freeze
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def absent
      unless @announced_absent
        @announced_absent = true
        @on_absent&.call(@path)
      end
      {}.freeze
    end
  end
end
