# frozen_string_literal: true

require "set"

module TutorialCatalog
  # The one door. Every surface reads through this and no other.
  #
  # Locale is part of every question. There is no "any locale" query, so an
  # English video cannot leak to a Dutch reader.
  class Catalog
    def initialize(curriculum_path:, tours_path: nil, manifest_path: nil, journeys: {}, on_manifest_absent: nil)
      @curriculum = Curriculum.new(curriculum_path)
      @tours = Tours.new(tours_path, journeys: journeys)
      @manifest = Manifest.new(manifest_path, on_absent: on_manifest_absent)
      @mutex = Mutex.new
      @by_locale = {}
    end

    # Every tutorial this locale can see, in course order.
    def all(locale:)
      resolved(locale.to_s)
    end

    def find(slug, locale:)
      resolved(locale.to_s).find { |tutorial| tutorial.slug == slug.to_s }
    end

    # Tutorials anchored to a page, in course order.
    #
    # `page_key` is a plain "controller#action" — what a framework produces and
    # what the curriculum stores, byte for byte. A `tab:` qualifier rides along
    # on the returned value but never narrows the match: the fragment that
    # selects a tab is not sent to the server.
    def for_page(page_key, locale:)
      key = page_key.to_s
      resolved(locale.to_s).select { |tutorial| anchor_routes(tutorial.slug).include?(key) }
    end

    # Tours anchored to a page, in file order.
    #
    # `step:` does narrow, because a wizard step is a path segment rather than a
    # fragment. An anchor with no step matches any step of its route.
    def tours_for_page(page_key, step: nil, locale:)
      key = page_key.to_s
      wanted_step = step&.to_s
      wanted_locale = locale.to_s

      @tours.entries.filter_map do |entry|
        next unless entry[:anchors].any? { |anchor| matches_step?(anchor, key, wanted_step) }

        title = tour_title(entry, wanted_locale)
        next if title.nil?

        Tour.new(key: entry[:key], title: title, locale: wanted_locale)
      end
    end

    def problems(known_routes:)
      Validation.problems(curriculum: @curriculum, tours: @tours, manifest: @manifest,
                          known_routes: known_routes)
    end

    def reload!
      @mutex.synchronize { @by_locale = {} }
      @curriculum.reload!
      @tours.reload!
      @manifest.reload!
      self
    end

    private

    def matches_step?(anchor, key, wanted_step)
      return false unless anchor[:route] == key
      return true if anchor[:step].nil?

      anchor[:step] == wanted_step
    end

    # A tour is offered only where both the journey and its title exist. Missing
    # either one means a reader would get half a walkthrough or none at all.
    def tour_title(entry, locale)
      locales = @tours.journey_locales(entry[:key])
      return nil unless locales.include?(locale)

      entry[:titles][locale]
    end

    # Resolved values are cached per locale, keyed off the manifest's current
    # state so a publish is picked up without a restart.
    def resolved(locale)
      videos = @manifest.videos

      @mutex.synchronize do
        cached = @by_locale[locale]
        next cached[:tutorials] if cached && cached[:videos].equal?(videos)

        tutorials = build(locale, videos)
        @by_locale[locale] = { videos: videos, tutorials: tutorials }
        tutorials
      end
    end

    def build(locale, videos)
      visible = @curriculum.leaves.select { |leaf| visible?(leaf, locale) }

      visible.each_with_index.map do |leaf, index|
        previous = index.zero? ? nil : visible[index - 1]
        following = visible[index + 1]

        tutorial(leaf, locale, videos,
                 prev_slug: previous && previous[:slug],
                 next_slug: following && following[:slug])
      end.freeze
    end

    # A leaf whose declared locales exclude this one is absent rather than
    # planned: the curriculum is saying that video will never exist in this
    # language, and showing it as coming soon would be a promise nobody intends
    # to keep. A blocked leaf is an authoring note and never reader-facing.
    def visible?(leaf, locale)
      return false if leaf[:blocked]

      declared = leaf[:locales] || @curriculum.default_locales
      declared.include?(locale)
    end

    def tutorial(leaf, locale, videos, prev_slug:, next_slug:)
      entry = videos.dig(leaf[:slug], locale)

      Tutorial.new(
        slug: leaf[:slug],
        number: leaf[:number],
        title: title_for(leaf, locale),
        scope: leaf[:scope],
        chapter_number: leaf[:chapter_number],
        chapter_title: leaf[:chapter_title],
        subchapter_number: leaf[:subchapter_number],
        subchapter_title: leaf[:subchapter_title],
        locale: locale,
        tab: leaf[:anchors].filter_map { |anchor| anchor[:tab] }.first,
        status: entry ? :watchable : :planned,
        url: entry && entry["url"],
        poster: entry && entry["poster"],
        captions: entry && entry["captions"],
        version: entry && entry["version"],
        duration: entry && entry["duration"],
        prev_slug: prev_slug,
        next_slug: next_slug
      )
    end

    # Falls back to English, never to the slug. Locale strictness is about
    # videos; a row with no words is worse than a row in the wrong language.
    def title_for(leaf, locale)
      titles = leaf[:titles]
      titles[locale] || titles["en"] || titles.values.first
    end

    def anchor_routes(slug)
      @anchor_routes ||= @curriculum.leaves.to_h do |leaf|
        [ leaf[:slug], leaf[:anchors].map { |anchor| anchor[:route] }.to_set ]
      end
      @anchor_routes.fetch(slug, Set.new)
    end
  end
end
