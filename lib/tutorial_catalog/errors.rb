# frozen_string_literal: true

module TutorialCatalog
  Error = Class.new(StandardError)

  # The curriculum is committed and CI-checked, so a missing or unparseable one
  # is a deploy bug rather than a race. It is never rescued into a quiet empty
  # library — an empty library looks like a product that teaches nothing.
  CurriculumError = Class.new(Error)
end
