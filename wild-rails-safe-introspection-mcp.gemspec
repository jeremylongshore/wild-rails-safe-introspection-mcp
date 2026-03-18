# frozen_string_literal: true

require_relative 'lib/wild_rails_safe_introspection/version'

Gem::Specification.new do |spec|
  spec.name = 'wild-rails-safe-introspection-mcp'
  spec.version = WildRailsSafeIntrospection::VERSION
  spec.authors = ['Intent Solutions']
  spec.summary = 'Safe, governed, read-only Rails introspection via MCP'
  spec.description = 'MCP server providing policy-enforced, audited, read-only introspection ' \
                     'of live Rails applications. Allowlist-based model access with denylist ' \
                     'column stripping, row caps, query timeouts, and full audit trail.'
  spec.homepage = 'https://github.com/jeremylongshore/wild-rails-safe-introspection-mcp'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb', 'config/**/*.yml', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 7.0', '< 9.0'
  spec.add_dependency 'mcp', '~> 0.8'
  spec.add_dependency 'yaml'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
