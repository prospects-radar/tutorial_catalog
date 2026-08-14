# frozen_string_literal: true

require "yaml"

module TutorialCatalog
  # Written walkthroughs, anchored the same way videos are.
  #
  # Anchors live app-side rather than inside the tour files, because the tour
  # source maps a key straight to its step array with no slot for metadata —
  # anchoring there would mean changing that schema. Keeping them separate also
  # stops a video coverage ledger from counting two different things.
  #
  # `step:` is the one place this vocabulary differs from a video's. A tab lives
  # in the URL fragment and never reaches the server, so it cannot narrow; a
  # wizard step is a path segment, so it can — and must, since a whole wizard's
  # tours share one route.
  class Tours
    def initialize(path, journeys:)
      @path = path
      @journeys = journeys
      @mutex = Mutex.new
    end

    # [{ key:, titles: { "en" => ... }, anchors: [{ route:, step: }] }]
    def entries
      @entries || @mutex.synchronize { @entries ||= parse }
    end

    def keys = entries.map { |entry| entry[:key] }

    # Journey keys the source knows about, whether or not they are anchored.
    def known_journeys = journeys.keys.map(&:to_s)

    # The locales a journey exists in, read from its first step's title map.
    def journey_locales(key)
      steps = journeys[key.to_s] || journeys[key.to_sym]
      title = Array(steps).first&.dig("title")
      title.is_a?(Hash) ? title.keys.map(&:to_s) : []
    end

    def reload!
      @mutex.synchronize { @entries = nil }
      @journeys_cache = nil
      self
    end

    private

    def journeys
      @journeys_cache ||= (@journeys.respond_to?(:call) ? @journeys.call : @journeys) || {}
    end

    def parse
      return [].freeze unless @path && File.exist?(@path)

      document = YAML.load_file(@path)
      return [].freeze unless document.is_a?(Hash)

      Array(document["tours"]).map { |key, body| entry(key, body || {}) }.freeze
    rescue Psych::Exception => e
      raise CurriculumError, "#{@path} is not parseable: #{e.message}"
    end

    def entry(key, body)
      {
        key: key.to_s,
        titles: titles(body["title"]),
        anchors: Array(body["pages"]).filter_map do |page|
          next unless page.is_a?(Hash) && page["route"]

          { route: page["route"].to_s, step: page["step"]&.to_s }
        end.freeze
      }.freeze
    end

    def titles(value)
      case value
      when Hash then value.to_h { |locale, text| [ locale.to_s, text.to_s ] }.freeze
      when nil then {}.freeze
      else { "en" => value.to_s }.freeze
      end
    end
  end
end
