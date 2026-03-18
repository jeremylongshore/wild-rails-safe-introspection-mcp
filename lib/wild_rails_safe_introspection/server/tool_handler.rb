# frozen_string_literal: true

module WildRailsSafeIntrospection
  module Server
    module ToolHandler
      def self.execute(action:, resource:, server_context:)
        api_key = server_context&.dig(:api_key)
        request_context = Identity::IdentityResolver.resolve(api_key: api_key)

        unless Identity::CapabilityGate.permitted?(request_context, action: action, resource: resource)
          denial = Identity::CapabilityGate.denial_response
          audit_gate_denial(action, resource, request_context, denial)
          return format_response(denial)
        end

        guard_result = yield(request_context)
        format_response(guard_result)
      end

      def self.format_response(result)
        error = %i[denied error].include?(result[:status])
        content = [{ type: 'text', text: JSON.generate(result) }]

        MCP::Tool::Response.new(content, error: error)
      end
      private_class_method :format_response

      def self.audit_gate_denial(action, resource, request_context, denial)
        Audit::Recorder.record(
          tool_name: action,
          model_name: resource.to_s,
          parameters: {},
          request_context: request_context
        ) { denial }
      end
      private_class_method :audit_gate_denial
    end
  end
end
