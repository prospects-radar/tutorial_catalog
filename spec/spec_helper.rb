# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "tutorial_catalog"

def fixture(name) = File.expand_path("fixtures/#{name}", __dir__)

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end
