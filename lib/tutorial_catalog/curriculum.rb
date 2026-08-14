# frozen_string_literal: true

require "yaml"

module TutorialCatalog
  # Reads the committed curriculum file and flattens it into leaf records.
  #
  # Parsed lazily on first use — a process that never asks about tutorials should
  # not pay for a few thousand lines of YAML — then held for the life of the
  # object. The file is committed and changes only on deploy, so there is nothing
  # to invalidate; callers who edit it in development call `reload!`.
  #
  # A leaf record is a plain Hash with symbol keys. It is deliberately not a
  # Tutorial: a Tutorial is locale-resolved and status-joined, and neither of
  # those is knowable here.
  class Curriculum
    def initialize(path)
      @path = path
      @mutex = Mutex.new
    end

    # Every leaf, in the order the file lists them, which is course order.
    def leaves
      @leaves || @mutex.synchronize { @leaves ||= parse }
    end

    def default_locales
      leaves # force the parse, which sets @default_locales
      @default_locales
    end

    # The declared tracks, in file order: [{ name:, titles:, members: }].
    #
    # `members` is the hand-written list beside the track. It is NOT what the
    # catalog groups by — a leaf's own `tracks:` is, because a list kept
    # somewhere else is exactly how content drifts out of reach. The list is
    # kept so the checks can say when the two disagree.
    def track_definitions
      leaves # force the parse
      @track_definitions
    end

    def reload!
      @mutex.synchronize do
        @leaves = nil
        @default_locales = nil
        @track_definitions = nil
      end
      self
    end

    private

    def parse
      raise CurriculumError, "no curriculum at #{@path}" unless @path && File.exist?(@path)

      document = load_document
      @default_locales = Array(document["default_locales"]).map(&:to_s)
      @default_locales = %w[en] if @default_locales.empty?
      @track_definitions = track_definitions_from(document)

      flatten(document)
    rescue Psych::Exception => e
      raise CurriculumError, "#{@path} is not parseable: #{e.message}"
    end

    def load_document
      document = YAML.load_file(@path)
      raise CurriculumError, "#{@path} does not describe a curriculum" unless document.is_a?(Hash)

      document
    end

    def flatten(document)
      Array(document["chapters"]).flat_map do |chapter|
        Array(chapter["subchapters"]).flat_map do |subchapter|
          Array(subchapter["leaves"]).map { |leaf| record(leaf, chapter, subchapter) }
        end
      end.freeze
    end

    def track_definitions_from(document)
      Array(document["tracks"]).filter_map do |track|
        next unless track.is_a?(Hash) && track["name"]

        {
          name: track["name"].to_s,
          titles: stringify(track["title"]),
          members: Array(track["members"]).map(&:to_s).freeze
        }.freeze
      end.freeze
    end

    def record(leaf, chapter, subchapter)
      {
        slug: leaf["slug"].to_s,
        number: leaf["number"].to_s,
        titles: stringify(leaf["title"]),
        scope: leaf["scope"],
        blocked: leaf["blocked"].to_s.strip != "",
        locales: leaf.key?("locales") ? Array(leaf["locales"]).map(&:to_s) : nil,
        tracks: Array(leaf["tracks"]).map(&:to_s).freeze,
        anchors: anchors(leaf),
        chapter_number: chapter["number"],
        chapter_title: chapter["title"],
        subchapter_number: subchapter["number"].to_s,
        subchapter_title: subchapter["title"]
      }.freeze
    end

    # `route` is the whole match. `tab` rides along so a client-side filter can
    # be added later without a curriculum migration, but it never narrows —
    # a URL fragment is not sent to the server, so the request for a tabbed page
    # is byte-identical whichever tab is showing.
    def anchors(leaf)
      Array(leaf["pages"]).filter_map do |page|
        next unless page.is_a?(Hash) && page["route"]

        { route: page["route"].to_s, tab: page["tab"]&.to_s }
      end.freeze
    end

    def stringify(titles)
      case titles
      when Hash then titles.to_h { |locale, text| [ locale.to_s, text.to_s ] }.freeze
      when nil then {}.freeze
      else { "en" => titles.to_s }.freeze
      end
    end
  end
end
