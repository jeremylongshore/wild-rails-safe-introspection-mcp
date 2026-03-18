# frozen_string_literal: true

require 'active_record'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

ActiveRecord::Schema.verbose = false

require_relative 'support/test_schema'
require_relative 'support/test_models'

require 'wild_rails_safe_introspection'
require_relative 'support/test_config_helper'

RSpec.configure do |config|
  config.include TestConfigHelper

  config.before do
    WildRailsSafeIntrospection.reset!
    WildRailsSafeIntrospection::Adapter::ConnectionManager.reset!
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
