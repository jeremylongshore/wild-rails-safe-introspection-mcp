# frozen_string_literal: true

require_relative 'wild_rails_safe_introspection/version'
require_relative 'wild_rails_safe_introspection/configuration'
require_relative 'wild_rails_safe_introspection/adapter/write_prevention'
require_relative 'wild_rails_safe_introspection/adapter/model_resolver'
require_relative 'wild_rails_safe_introspection/adapter/model_reflector'
require_relative 'wild_rails_safe_introspection/adapter/schema_inspector'
require_relative 'wild_rails_safe_introspection/adapter/connection_manager'
require_relative 'wild_rails_safe_introspection/adapter/record_lookup'
require_relative 'wild_rails_safe_introspection/adapter/filtered_lookup'
require_relative 'wild_rails_safe_introspection/guard/column_resolver'
require_relative 'wild_rails_safe_introspection/guard/result_filter'
require_relative 'wild_rails_safe_introspection/guard/query_guard'

module WildRailsSafeIntrospection
  class Error < StandardError; end
  class ConfigError < Error; end
  class ModelNotAllowedError < Error; end
  class WriteAttemptError < Error; end
  class QueryTimeoutError < Error; end

  class << self
    def configure
      yield(configuration)
      configuration.load!
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset!
      @configuration = nil
    end
  end
end
