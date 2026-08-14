# frozen_string_literal: true

module TutorialCatalog
  # Static checks over the parsed config, as pure functions.
  #
  # They read the same parse the catalog itself reads, so a check cannot drift
  # from what the runtime does. The route set is passed in rather than reached
  # for: the router belongs to the host application, and this gem does not know
  # what a request is.
  #
  # Severity is an opinion, not an action. The caller decides what aborts.
  module Validation
    # Namespaces no end-user tutorial should ever point at.
    INTERNAL_NAMESPACES = %w[api system_admin dev raaf tracing].freeze

    module_function

    def problems(curriculum:, tours:, manifest:, known_routes:)
      known = Array(known_routes).map(&:to_s).to_set

      anchor_problems(curriculum, tours, known) +
        unanchored_journeys(tours) +
        untitled_tours(tours) +
        journey_locale_gaps(curriculum, tours) +
        track_membership_drift(curriculum) +
        orphan_videos(curriculum, manifest)
    end

    # Every anchor must name a route that exists, and none may sit in an
    # internal namespace. An anchor naming a route that does not exist is a
    # tutorial that silently appears nowhere, which is why this is an error.
    def anchor_problems(curriculum, tours, known)
      anchors(curriculum, tours).flat_map do |route, subject|
        if internal?(route)
          [ Problem.new(severity: :error, kind: :internal_namespace, subject: route,
                        message: "#{subject} anchors to #{route}, which is staff-only") ]
        elsif !known.include?(route)
          [ Problem.new(severity: :error, kind: :unknown_route, subject: route,
                        message: "#{subject} anchors to #{route}, which is not a route") ]
        else
          []
        end
      end
    end

    def anchors(curriculum, tours)
      from_leaves = curriculum.leaves.flat_map do |leaf|
        leaf[:anchors].map { |anchor| [ anchor[:route], "leaf #{leaf[:slug]}" ] }
      end
      from_tours = tours.entries.flat_map do |entry|
        entry[:anchors].map { |anchor| [ anchor[:route], "tour #{entry[:key]}" ] }
      end

      (from_leaves + from_tours).uniq
    end

    def internal?(route)
      INTERNAL_NAMESPACES.any? { |namespace| route.start_with?("#{namespace}/") }
    end

    # A journey the anchor file never names is authored content nobody can
    # reach — the exact failure this whole surface exists to end. Reported as a
    # warning rather than an error, because it is the status quo for content
    # that predates anchoring: promoting it to an error would fail the build on
    # tours nobody has decided the fate of yet.
    def unanchored_journeys(tours)
      anchored = tours.keys.to_set

      (tours.known_journeys - anchored.to_a).sort.map do |key|
        Problem.new(severity: :warning, kind: :unanchored_journey, subject: key,
                    message: "journey #{key} is not anchored, so nothing can offer it")
      end
    end

    # A tour is offered only where both the journey and its title exist, so a
    # journey with a locale the anchor file has no title for is half-reachable.
    def untitled_tours(tours)
      tours.entries.flat_map do |entry|
        missing = tours.journey_locales(entry[:key]) - entry[:titles].keys
        next [] if missing.empty? || tours.journey_locales(entry[:key]).empty?

        [ Problem.new(severity: :error, kind: :untitled_tour, subject: entry[:key],
                      message: "tour #{entry[:key]} exists in #{missing.join(', ')} but has no title there") ]
      end
    end

    # Where each anchored journey actually exists, against the locales the
    # curriculum declares. `untitled_tours` above asks whether the anchor file
    # has a *label* for a locale; this asks whether the walkthrough itself was
    # ever written there. Both can be true at once and they are fixed in
    # different files, so they are reported apart.
    #
    # A journey the source does not define at all is the degenerate case —
    # it exists nowhere — and gets its own kind, because the fix is to remove
    # the anchor or write the tour rather than to translate anything.
    def journey_locale_gaps(curriculum, tours)
      declared = curriculum.default_locales

      tours.entries.flat_map do |entry|
        present = tours.journey_locales(entry[:key])

        if present.empty?
          [ Problem.new(severity: :warning, kind: :unknown_journey, subject: entry[:key],
                        message: "tour #{entry[:key]} is anchored but no journey defines it") ]
        elsif (missing = declared - present).any?
          [ Problem.new(severity: :warning, kind: :journey_locale_gap, subject: entry[:key],
                        message: "journey #{entry[:key]} exists in #{present.sort.join(', ')} " \
                                 "but not in #{missing.sort.join(', ')}") ]
        else
          []
        end
      end
    end

    # A track's `members:` list is not what groups the leaves — a leaf's own
    # `tracks:` is — so a stale list changes nothing a reader sees. It is still
    # the shape of drift this whole surface exists to end, so it is reported
    # rather than left to rot silently.
    def track_membership_drift(curriculum)
      actual = Hash.new { |hash, key| hash[key] = [] }
      curriculum.leaves.each do |leaf|
        leaf[:tracks].each { |name| actual[name] << leaf[:slug] }
      end

      curriculum.track_definitions.filter_map do |definition|
        listed = definition[:members]
        grouped = actual[definition[:name]]
        difference = (listed - grouped) | (grouped - listed)
        next if difference.empty?

        Problem.new(severity: :warning, kind: :track_membership_drift, subject: definition[:name],
                    message: "track #{definition[:name]} lists members that disagree with the " \
                             "leaves' own tracks: #{difference.sort.join(', ')}")
      end
    end

    # A published file with no leaf cannot be rendered by anything, so it is
    # housekeeping rather than breakage — a warning until the directory is clean.
    def orphan_videos(curriculum, manifest)
      slugs = curriculum.leaves.map { |leaf| leaf[:slug] }.to_set

      (manifest.slugs - slugs.to_a).sort.map do |slug|
        Problem.new(severity: :warning, kind: :orphan_video, subject: slug,
                    message: "#{slug} is published but no leaf names it")
      end
    end
  end
end
