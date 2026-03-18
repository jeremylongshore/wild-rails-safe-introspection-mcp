# frozen_string_literal: true

module WildRailsSafeIntrospection
  module Server
    module ServerFactory
      TOOLS = [
        Tools::InspectModelSchema,
        Tools::LookupRecordById,
        Tools::FindRecordsByFilter
      ].freeze

      def self.create(server_context: {})
        MCP::Server.new(
          name: 'wild-rails-safe-introspection',
          version: WildRailsSafeIntrospection::VERSION,
          tools: TOOLS,
          server_context: server_context
        )
      end
    end
  end
end
