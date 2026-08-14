# frozen_string_literal: true

require "tutorial_catalog/version"
require "tutorial_catalog/errors"
require "tutorial_catalog/tutorial"
require "tutorial_catalog/tour"
require "tutorial_catalog/problem"
require "tutorial_catalog/curriculum"
require "tutorial_catalog/manifest"
require "tutorial_catalog/tours"
require "tutorial_catalog/validation"
require "tutorial_catalog/catalog"

# What teaches this page?
#
# Two sources answer that, and they are not equally trustworthy:
#
#   the curriculum   what tutorials exist, where each belongs, what it covers.
#                    Committed, checked in CI, changes only on deploy.
#   the manifest     which of them actually play, and at what URL.
#                    Written by a publish step onto a live mount, so it changes
#                    under a running process and can be caught mid-write.
#
# The catalog joins them and answers page-scoped and course-ordered questions in
# one locale at a time. It is plain Ruby: no Rails, no database, no notion of a
# request. Callers pass paths in, and pass the route set in when they want it
# validated.
module TutorialCatalog
end
