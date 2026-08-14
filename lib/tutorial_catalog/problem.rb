# frozen_string_literal: true

module TutorialCatalog
  # Something the static checks found. `severity` is the catalog's opinion; the
  # caller decides whether to abort on it.
  Problem = Data.define(:severity, :kind, :subject, :message)
end
