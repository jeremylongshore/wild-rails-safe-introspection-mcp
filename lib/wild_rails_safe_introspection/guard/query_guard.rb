# frozen_string_literal: true

module WildRailsSafeIntrospection
  module Guard
    module QueryGuard
      DENIAL_RESPONSE = {
        status: :denied,
        reason: :model_not_allowed,
        message: 'The requested model is not on the access allowlist.'
      }.freeze

      def self.inspect_schema(model_name)
        Audit::Recorder.record(tool_name: 'inspect_model_schema', model_name: model_name, parameters: {}) do
          accessible = ColumnResolver.accessible_columns(model_name)
          next DENIAL_RESPONSE unless accessible

          result = Adapter::SchemaInspector.inspect_schema(model_name)
          next result unless result[:status] == :ok

          result.merge(
            columns: ResultFilter.filter_schema_columns(result[:columns], accessible)
          )
        end
      end

      def self.find_by_id(model_name, id)
        Audit::Recorder.record(tool_name: 'lookup_record_by_id', model_name: model_name, parameters: { id: id }) do
          accessible = ColumnResolver.accessible_columns(model_name)
          next DENIAL_RESPONSE unless accessible

          result = Adapter::RecordLookup.find_by_id(model_name, id)
          next result unless result[:status] == :ok

          result.merge(
            record: ResultFilter.filter_record(result[:record], accessible)
          )
        end
      end

      def self.find_by_filter(model_name, field:, value:) # rubocop:disable Metrics/MethodLength
        params = { field: field, value: value }
        Audit::Recorder.record(
          tool_name: 'find_records_by_filter', model_name: model_name, parameters: params
        ) do
          accessible = ColumnResolver.accessible_columns(model_name)
          next DENIAL_RESPONSE unless accessible
          next DENIAL_RESPONSE unless accessible.include?(field.to_s)

          result = Adapter::FilteredLookup.find_by_filter(model_name, field: field, value: value)
          next result unless result[:status] == :ok

          result.merge(
            records: ResultFilter.filter_records(result[:records], accessible)
          )
        end
      end
    end
  end
end
