# frozen_string_literal: true

module TutorialCatalog
  # A written walkthrough, resolved for one locale.
  #
  # A sibling of Tutorial rather than a subtype: a tour has no url, poster,
  # captions, version or course position, and five permanently-nil fields are
  # worth more as an absent type than as absent data.
  Tour = Data.define(:key, :title, :locale)
end
