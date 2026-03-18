# frozen_string_literal: true

module TestConfigHelper
  FIXTURES_PATH = File.expand_path('../fixtures', __dir__)

  def configure_with_test_fixtures!
    WildRailsSafeIntrospection.configure do |config|
      config.access_policy_path = File.join(FIXTURES_PATH, 'access_policy.yml')
      config.blocked_resources_path = File.join(FIXTURES_PATH, 'blocked_resources.yml')
    end
  end
end
