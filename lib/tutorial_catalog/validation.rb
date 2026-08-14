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
    # reach — the exact failure this whole surface exists to end.
    def unanchored_journeys(tours)
      anchored = tours.keys.to_set

      (tours.known_journeys - anchored.to_a).sort.map do |key|
        Problem.new(severity: :error, kind: :unanchored_journey, subject: key,
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
