# frozen_string_literal: true

require "set"

module TutorialCatalog
  # The one door. Every surface reads through this and no other.
  #
  # Locale is part of every question. There is still no "any locale" query: the
  # curriculum decides which leaves a language sees, and a leaf it declares
  # English-only stays out of the Dutch library entirely.
  #
  # What does cross the line is the file. A leaf declared in both languages but
  # rendered in only one is watchable in both, playing the `fallback_locale:`
  # render where its own is missing — the alternative is a "coming soon" row for
  # a video that exists, which is a worse answer to "teach me this page" than
  # subtitled English. The Tutorial says which language it ended up in, so the
  # surface can mark it.
  class Catalog
    EMPTY_ROUTES = Set.new.freeze

    def initialize(curriculum_path:, tours_path: nil, manifest_path: nil, journeys: {},
                   on_manifest_absent: nil, on_manifest_malformed: nil, watch_curriculum: false,
                   fallback_locale: "en")
      @curriculum = Curriculum.new(curriculum_path, watch: watch_curriculum)
      @tours = Tours.new(tours_path, journeys: journeys)
      @manifest = Manifest.new(manifest_path, on_absent: on_manifest_absent,
                                              on_malformed: on_manifest_malformed)
      # Nil turns the fallback off, and so does an empty string — this is
      # configuration, and configuration arrives blank.
      @fallback_locale = fallback_locale.to_s == "" ? nil : fallback_locale.to_s
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

    # Tutorials anchored to a page, most useful on that page first.
    #
    # `page_key` is a plain "controller#action" — what a framework produces and
    # what the curriculum stores, byte for byte. A `tab:` qualifier rides along
    # on the returned value but never narrows the match: the fragment that
    # selects a tab is not sent to the server.
    #
    # Order is the page's own claim where it made one, and course order where it
    # did not. A page with room for three of its nine leaves needs to say which
    # three, and the same leaf can be the first thing to watch on one page and a
    # footnote on another — which is why the rank is on the anchor rather than on
    # the leaf. A page that ranked nothing is unchanged: course order throughout.
    def for_page(page_key, locale:, track: nil)
      key = page_key.to_s
      routes = anchor_routes
      anchored = resolved(locale.to_s).select { |tutorial| routes.fetch(tutorial.slug, EMPTY_ROUTES).include?(key) }

      by_rank(narrow(anchored, track), key).freeze
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
      end.freeze
    end

    def problems(known_routes:)
      Validation.problems(curriculum: @curriculum, tours: @tours, manifest: @manifest,
                          known_routes: known_routes).freeze
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
    # Ranked leaves first, in the order the page asked for; everything the page
    # said nothing about after them, in course order. Unranked is not
    # last-ranked in the sense of being demoted — it is the page declining to
    # have an opinion, and course order is the answer to that.
    #
    # `sort_by` with the index as a tiebreak rather than a bare sort: Ruby's
    # sort is not stable, and course order among the unranked is the whole point
    # of leaving them unranked.
    def by_rank(tutorials, page_key)
      ranks = anchor_ranks(page_key)

      tutorials.each_with_index.sort_by do |tutorial, index|
        [ ranks[tutorial.slug] || Float::INFINITY, index ]
      end.map(&:first)
    end

    # What each leaf's anchor ON THIS PAGE claimed, for the leaves that claimed
    # anything. A leaf anchored to the page more than once takes its first
    # ranked anchor, because two ranks for one page is an authoring mistake and
    # the first is as good an answer as any.
    def anchor_ranks(page_key)
      @curriculum.leaves.each_with_object({}) do |leaf, ranks|
        anchor = leaf[:anchors].find { |candidate| candidate[:route] == page_key && candidate[:rank] }
        ranks[leaf[:slug]] = anchor[:rank] if anchor
      end
    end

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
    # Keyed off both sources by identity. A re-parse hands back a new frozen
    # array, so an unchanged one is the same object and costs a comparison —
    # and a curriculum edited under a watching process invalidates this cache
    # rather than being resolved once and remembered forever.
    def resolved(locale)
      videos = @manifest.videos
      leaves = @curriculum.leaves

      @mutex.synchronize do
        cached = @by_locale[locale]
        next cached[:tutorials] if cached && cached[:videos].equal?(videos) && cached[:leaves].equal?(leaves)

        tutorials = build(locale, videos, leaves)
        @by_locale[locale] = { videos: videos, leaves: leaves, tutorials: tutorials }
        tutorials
      end
    end

    def build(locale, videos, leaves)
      visible = leaves.select { |leaf| visible?(leaf, locale) }

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
      entry, media_locale = media(videos, leaf[:slug], locale)

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
        media_locale: media_locale,
        page_key: leaf[:anchors].first&.[](:route),
        tab: leaf[:anchors].filter_map { |anchor| anchor[:tab] }.first,
        tracks: leaf[:tracks],
        status: entry ? :watchable : :planned,
        url: entry && entry["url"],
        poster: entry && entry["poster"],
        thumb: entry && entry["thumb"],
        captions: entry && entry["captions"],
        version: entry && entry["version"],
        duration: entry && entry["duration"],
        references: entry ? Array(entry["references"]) : [],
        prev_slug: prev_slug,
        next_slug: next_slug
      )
    end

    # Which file this leaf plays for this reader, and what language it is in.
    #
    # Their own language first, always: a Dutch render is what a Dutch reader
    # asked for, and it wins even when both exist. The fallback is reached only
    # where their own is absent, which is the state a render sweep passes
    # through — English lands first and Dutch follows a day later, and for that
    # day the leaf teaches rather than promising.
    #
    # Returns [nil, locale] when neither exists, which is a planned leaf: there
    # is no file, so the only honest answer to "what language is it in" is the
    # one the reader asked for.
    def media(videos, slug, locale)
      own = videos.dig(slug, locale)
      return [ own, locale ] if own
      return [ nil, locale ] if @fallback_locale.nil? || @fallback_locale == locale

      borrowed = videos.dig(slug, @fallback_locale)
      borrowed ? [ borrowed, @fallback_locale ] : [ nil, locale ]
    end

    # Falls back to English, never to the slug: a row with no words is worse
    # than a row in the wrong language. Unlike the video fallback, this one is
    # silent — an untranslated title is an authoring gap to be filled, not a
    # fact about the leaf worth telling the reader.
    # Takes anything carrying a `:titles` map — a leaf or a track definition.
    def title_for(node, locale) = resolve(node[:titles], locale)

    # Every piece of authored text on this surface resolves the same way, so a
    # translated leaf cannot end up sitting under an untranslated chapter.
    def resolve(titles, locale)
      titles[locale] || titles["en"] || titles.values.first
    end

    # Rebuilt whenever the parse behind it changes, for the same reason the
    # resolved cache is. Built once per call rather than per leaf, since
    # `for_page` asks about every tutorial in the locale.
    def anchor_routes
      leaves = @curriculum.leaves
      return @anchor_routes if @anchor_routes_for.equal?(leaves)

      @anchor_routes = leaves.to_h do |leaf|
        [ leaf[:slug], leaf[:anchors].map { |anchor| anchor[:route] }.to_set ]
      end.freeze
      @anchor_routes_for = leaves
      @anchor_routes
    end
  end
end
