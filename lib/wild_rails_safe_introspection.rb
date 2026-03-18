# frozen_string_literal: true

require 'json'
require 'mcp'

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
require_relative 'wild_rails_safe_introspection/audit/audit_record'
require_relative 'wild_rails_safe_introspection/audit/parameter_sanitizer'
require_relative 'wild_rails_safe_introspection/audit/audit_logger'
require_relative 'wild_rails_safe_introspection/audit/recorder'
require_relative 'wild_rails_safe_introspection/identity/request_context'
require_relative 'wild_rails_safe_introspection/identity/identity_resolver'
require_relative 'wild_rails_safe_introspection/identity/capability_gate'
require_relative 'wild_rails_safe_introspection/guard/query_guard'
require_relative 'wild_rails_safe_introspection/server/tool_handler'
require_relative 'wild_rails_safe_introspection/server/tools/inspect_model_schema'
require_relative 'wild_rails_safe_introspection/server/tools/lookup_record_by_id'
require_relative 'wild_rails_safe_introspection/server/tools/find_records_by_filter'
require_relative 'wild_rails_safe_introspection/server/server_factory'

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
