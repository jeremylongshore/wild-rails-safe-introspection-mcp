# frozen_string_literal: true

require 'yaml'

module WildRailsSafeIntrospection
  class Configuration
    CONSTANT_NAME_PATTERN = /\A[A-Z][A-Za-z0-9]*(::[A-Z][A-Za-z0-9]*)*\z/

    attr_accessor :access_policy_path, :blocked_resources_path
    attr_reader :defaults, :model_registry, :blocked_models, :blocked_columns

    def initialize
      @access_policy_path = nil
      @blocked_resources_path = nil
      @defaults = { 'max_rows' => 50, 'query_timeout_ms' => 5000 }
      @model_registry = {}
      @blocked_models = []
      @blocked_columns = []
    end

    def load!
      validate_paths!
      load_access_policy!
      load_blocked_resources!
      build_model_registry!
      freeze_policy_data!
    end

    def resolve_model(name)
      @model_registry[name]&.fetch(:klass, nil)
    end

    def model_allowed?(name)
      @model_registry.key?(name)
    end

    def model_config(name)
      @model_registry[name]
    end

    private

    def validate_paths!
      raise ConfigError, 'access_policy_path is required' unless @access_policy_path
      raise ConfigError, 'blocked_resources_path is required' unless @blocked_resources_path

      validate_file_exists!(@access_policy_path, 'access_policy')
      validate_file_exists!(@blocked_resources_path, 'blocked_resources')
    end

    def load_access_policy!
      data = YAML.safe_load_file(@access_policy_path)
      raise ConfigError, 'access_policy.yml must contain a version field' unless data&.key?('version')

      @defaults = @defaults.merge(data['defaults'] || {})
      @allowed_models_config = data['allowed_models'] || []
    end

    def load_blocked_resources!
      data = YAML.safe_load_file(@blocked_resources_path)
      raise ConfigError, 'blocked_resources.yml must contain a version field' unless data&.key?('version')

      @blocked_models = (data['blocked_models'] || []).freeze
      @blocked_columns = (data['blocked_columns'] || []).freeze
    end

    def build_model_registry!
      @model_registry = {}
      @allowed_models_config.each do |model_entry|
        register_model(model_entry)
      end
    end

    def register_model(model_entry)
      name = model_entry['name']
      return if @blocked_models.include?(name)

      klass = safe_resolve_constant(name)
      return unless klass

      @model_registry[name] = build_model_entry(klass, model_entry)
    end

    def build_model_entry(klass, model_entry)
      {
        klass: klass,
        columns_mode: resolve_columns_mode(model_entry['columns']),
        explicit_columns: resolve_explicit_columns(model_entry['columns']),
        max_rows: model_entry['max_rows'] || @defaults['max_rows'],
        query_timeout_ms: model_entry['query_timeout_ms'] || @defaults['query_timeout_ms']
      }
    end

    def validate_file_exists!(path, label)
      raise ConfigError, "#{label} not found: #{path}" unless File.exist?(path)
    end

    def safe_resolve_constant(name)
      return nil unless name.is_a?(String) && name.match?(CONSTANT_NAME_PATTERN)

      Object.const_get(name)
    rescue NameError
      nil
    end

    def resolve_columns_mode(columns)
      case columns
      when 'all' then :all
      when Array then :explicit
      else :all_except_blocked
      end
    end

    def resolve_explicit_columns(columns)
      columns.is_a?(Array) ? columns.map(&:to_s) : nil
    end

    def freeze_policy_data!
      @defaults.freeze
      @model_registry.each_value(&:freeze)
      @model_registry.freeze
    end
  end
end
