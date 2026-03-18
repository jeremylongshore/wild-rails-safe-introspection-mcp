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
        accessible = ColumnResolver.accessible_columns(model_name)
        return DENIAL_RESPONSE unless accessible

        result = Adapter::SchemaInspector.inspect_schema(model_name)
        return result unless result[:status] == :ok

        result.merge(
          columns: ResultFilter.filter_schema_columns(result[:columns], accessible)
        )
      end

      def self.find_by_id(model_name, id)
        accessible = ColumnResolver.accessible_columns(model_name)
        return DENIAL_RESPONSE unless accessible

        result = Adapter::RecordLookup.find_by_id(model_name, id)
        return result unless result[:status] == :ok

        result.merge(
          record: ResultFilter.filter_record(result[:record], accessible)
        )
      end

      def self.find_by_filter(model_name, field:, value:)
        accessible = ColumnResolver.accessible_columns(model_name)
        return DENIAL_RESPONSE unless accessible
        return DENIAL_RESPONSE unless accessible.include?(field.to_s)

        result = Adapter::FilteredLookup.find_by_filter(model_name, field: field, value: value)
        return result unless result[:status] == :ok

        result.merge(
          records: ResultFilter.filter_records(result[:records], accessible)
        )
      end
    end
  end
end
