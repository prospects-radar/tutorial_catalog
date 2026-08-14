# frozen_string_literal: true

require_relative "lib/tutorial_catalog/version"

Gem::Specification.new do |spec|
  spec.name = "tutorial_catalog"
  spec.version = TutorialCatalog::VERSION
  spec.authors = [ "ProspectsRadar" ]
  spec.email = [ "bert.hajee@enterprisemodules.com" ]

  spec.summary = "Answers what teaches this page, from a curriculum file and a publish manifest."
  spec.description = <<~TEXT
    Two sources with different authorities: a committed curriculum file says what
    tutorials exist and where each belongs, and a publish manifest says which of
    them actually play. The catalog joins them, resolves a locale, and answers
    page-scoped and course-ordered questions. Plain Ruby: no Rails, no database,
    no knowledge of what a request is.
  TEXT
  spec.homepage = "https://github.com/prospects-radar/prospects_radar"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = [ "lib" ]
end
