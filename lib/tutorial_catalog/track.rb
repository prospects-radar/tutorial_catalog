# frozen_string_literal: true

module TutorialCatalog
  # A subject running across the chapters — LinkedIn, automation, privacy —
  # resolved for one locale.
  #
  # `count` is how many leaves this locale can see in the track, so a caller can
  # render the size of a subject without asking for its leaves. It is total
  # rather than watchable, for the same reason the library's chapter rail counts
  # total: the number is there to show the shape of what the product teaches.
  Track = Data.define(:name, :title, :count)
end
