# frozen_string_literal: true

module WildRailsSafeIntrospection
  module Audit
    module Recorder
      def self.record(tool_name:, model_name:, parameters:)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

        emit_audit_record(tool_name, model_name, parameters, result, duration_ms)
        result
      end

      def self.build_audit_attrs(tool_name, model_name, parameters, result, duration_ms)
        {
          tool_name: tool_name, model_name: model_name,
          parameters: ParameterSanitizer.sanitize(tool_name, model_name, parameters),
          guard_result: map_guard_result(result), outcome: map_outcome(result),
          duration_ms: duration_ms, rows_returned: count_rows(result),
          error_message: result[:error_message]
        }
      end
      private_class_method :build_audit_attrs

      def self.emit_audit_record(tool_name, model_name, parameters, result, duration_ms)
        attrs = build_audit_attrs(tool_name, model_name, parameters, result, duration_ms)
        AuditLogger.log(AuditRecord.new(**attrs))
      end
      private_class_method :emit_audit_record

      def self.map_guard_result(result)
        case result[:status]
        when :ok, :not_found
          'allowed'
        when :denied
          "denied_#{result[:reason]}"
        when :error
          result[:reason] == :query_timeout ? 'denied_query_timeout' : "error_#{result[:reason]}"
        else
          'unknown'
        end
      end
      private_class_method :map_guard_result

      def self.map_outcome(result)
        case result[:status]
        when :ok, :not_found
          'success'
        when :denied
          'denied'
        when :error
          result[:reason] == :query_timeout ? 'timeout' : 'error'
        else
          'error'
        end
      end
      private_class_method :map_outcome

      def self.count_rows(result)
        return 0 unless result[:status] == :ok

        if result.key?(:record)
          result[:record] ? 1 : 0
        elsif result.key?(:records)
          result[:records].size
        else
          0
        end
      end
      private_class_method :count_rows
    end
  end
end
