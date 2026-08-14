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

    # Every tutorial this locale can see, in course order. `track:` narrows to
    # one subject — see `narrow`, which is where that means anything.
    def all(locale:, track: nil)
      narrow(resolved(locale.to_s), track)
    end

    def find(slug, locale:)
      resolved(locale.to_s).find { |tutorial| tutorial.slug == slug.to_s }
    end

    # The tracks worth offering this locale, in the order the curriculum lists
    # them. A track no visible leaf belongs to is omitted rather than shown
    # empty: a Dutch reader following a chip to nothing has been told the
    # subject exists in their language, which is the promise this whole surface
    # is built not to break.
    def tracks(locale:)
      wanted = locale.to_s
      counts = all(locale: wanted).flat_map(&:tracks).tally

      @curriculum.track_definitions.filter_map do |definition|
        count = counts[definition[:name]]
        next if count.nil?

        Track.new(name: definition[:name], title: title_for(definition, wanted), count: count)
      end.freeze
    end

    # Tutorials anchored to a page, in course order.
    #
    # `page_key` is a plain "controller#action" — what a framework produces and
    # what the curriculum stores, byte for byte. A `tab:` qualifier rides along
    # on the returned value but never narrows the match: the fragment that
    # selects a tab is not sent to the server.
    def for_page(page_key, locale:, track: nil)
      key = page_key.to_s
      anchored = resolved(locale.to_s).select { |tutorial| anchor_routes(tutorial.slug).include?(key) }

      narrow(anchored, track)
    end

    # What a library page shows: the whole curriculum, or what teaches one page,
    # or one subject, or a page narrowed to a subject.
    #
    # It lives here rather than in the caller so that "does this leaf belong to
    # this track" has exactly one implementation. The two filters are not the
    # same kind of thing — an anchor is a property of the leaf's page, a track
    # is a property of the leaf — but they compose, and a caller that composed
    # them itself would be a second answer to a question this object already
    # answers.
    def browse(page_key: nil, track: nil, locale:)
      return for_page(page_key, locale: locale, track: track) if page_key.to_s != ""

      all(locale: locale, track: track)
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

    # The one place that knows what track membership means. Narrowing does not
    # renumber the course: a leaf's `prev_slug` and `next_slug` still point at
    # its whole-course neighbours, so following them out of a track is possible,
    # and leaving the track is what a reader means by "next".
    def narrow(tutorials, track)
      wanted = track.to_s
      return tutorials if wanted == ""

      tutorials.select { |tutorial| tutorial.tracks.include?(wanted) }.freeze
    end

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
        chapter_title: resolve(leaf[:chapter_titles], locale),
        subchapter_number: leaf[:subchapter_number],
        subchapter_title: resolve(leaf[:subchapter_titles], locale),
        locale: locale,
        page_key: leaf[:anchors].first&.[](:route),
        tab: leaf[:anchors].filter_map { |anchor| anchor[:tab] }.first,
        tracks: leaf[:tracks],
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
    # Takes anything carrying a `:titles` map — a leaf or a track definition.
    def title_for(node, locale) = resolve(node[:titles], locale)

    # Every piece of authored text on this surface resolves the same way, so a
    # translated leaf cannot end up sitting under an untranslated chapter.
    def resolve(titles, locale)
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
