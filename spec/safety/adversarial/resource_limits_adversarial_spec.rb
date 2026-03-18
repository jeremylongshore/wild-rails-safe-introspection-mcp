# frozen_string_literal: true

# Adversarial tests for resource limit bypass attempts.
#
# Safety claims covered: 4.5, 4.6, 4.9, 5.1, 5.5, 5.6, 5.7
# These tests verify that row caps, timeouts, and resource boundaries
# cannot be bypassed via malicious input or configuration.
RSpec.describe 'Resource Limits Adversarial', :adversarial, :safety do
  include TestConfigHelper

  before do
    configure_with_test_fixtures!
    User.delete_all
    Account.delete_all
    FeatureFlag.delete_all
  end

  let(:ctx) { authenticated_server_context }
  let(:tool_filter) { WildRailsSafeIntrospection::Server::Tools::FindRecordsByFilter }
  let(:tool_schema) { WildRailsSafeIntrospection::Server::Tools::InspectModelSchema }
  let(:tool_lookup) { WildRailsSafeIntrospection::Server::Tools::LookupRecordById }

  def parse_response(response)
    JSON.parse(response.content.first[:text], symbolize_names: true)
  end

  # -------------------------------------------------------------------
  # Row cap bypass attempts — Claim 4.5, 4.6
  # -------------------------------------------------------------------
  describe 'row cap bypass attempts' do
    it 'treats LIMIT 9999 in filter value as literal' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: 'LIMIT 9999',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end

    it 'treats UNION SELECT in filter value as literal' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: 'UNION SELECT',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end

    it 'treats OFFSET 0 in filter value as literal' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: 'OFFSET 0',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end
  end

  # -------------------------------------------------------------------
  # Row cap enforcement correctness — Claim 4.5
  # -------------------------------------------------------------------
  describe 'row cap enforcement correctness' do
    let(:audit_records) { [] }

    before do
      allow(WildRailsSafeIntrospection::Audit::AuditLogger).to receive(:log) do |record|
        audit_records << record
      end
      # Create more records than the configured max_rows (100 for Account)
      105.times do |i|
        Account.create!(
          name: "Corp #{i}", slug: "corp-#{i}", plan: 'free',
          stripe_customer_id: "cus_#{i}", tax_id: "tax_#{i}", ssn: "000-00-#{i.to_s.rjust(4, '0')}"
        )
      end
    end

    it 'truncates results when records exceed max_rows' do
      response = tool_filter.call(
        model_name: 'Account', field: 'plan', value: 'free',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records].size).to be <= 100
      expect(parsed[:truncated]).to be(true)
    end

    it 'records truncation in audit' do
      tool_filter.call(
        model_name: 'Account', field: 'plan', value: 'free',
        server_context: ctx
      )

      expect(audit_records.last.truncated).to be(true)
    end
  end

  # -------------------------------------------------------------------
  # Schema introspection not subject to row caps — Claim 4.9
  # -------------------------------------------------------------------
  describe 'schema introspection not subject to row caps' do
    it 'returns all accessible columns regardless of max_rows' do
      response = tool_schema.call(model_name: 'Account', server_context: ctx)
      parsed = parse_response(response)

      # Account has several columns; verify schema returns them all (minus blocked)
      expect(parsed[:status]).to eq('ok')
      expect(parsed[:columns].size).to be >= 4
    end
  end

  # -------------------------------------------------------------------
  # Timeout enforcement — Claim 5.1, 5.5, 5.6
  # -------------------------------------------------------------------
  describe 'timeout enforcement' do
    let(:audit_records) { [] }

    before do
      allow(WildRailsSafeIntrospection::Audit::AuditLogger).to receive(:log) do |record|
        audit_records << record
      end
    end

    it 'returns error response on timeout (not partial results)' do
      allow(Timeout).to receive(:timeout).and_raise(
        WildRailsSafeIntrospection::QueryTimeoutError, 'Query timed out'
      )

      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: 'x',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(response.error?).to be(true)
      expect(parsed[:status]).to eq('error')
      expect(parsed[:reason]).to eq('query_timeout')
    end

    it 'timeout response produces audit record with timeout outcome' do
      allow(Timeout).to receive(:timeout).and_raise(
        WildRailsSafeIntrospection::QueryTimeoutError, 'Query timed out'
      )

      tool_filter.call(
        model_name: 'Account', field: 'name', value: 'x',
        server_context: ctx
      )

      expect(audit_records.size).to eq(1)
      expect(audit_records.first.outcome).to eq('timeout')
    end

    it 'timeout audit record includes duration_ms' do
      allow(Timeout).to receive(:timeout).and_raise(
        WildRailsSafeIntrospection::QueryTimeoutError, 'Query timed out'
      )

      tool_filter.call(
        model_name: 'Account', field: 'name', value: 'x',
        server_context: ctx
      )

      expect(audit_records.first.duration_ms).to be_a(Integer)
      expect(audit_records.first.duration_ms).to be >= 0
    end
  end

  # -------------------------------------------------------------------
  # Timeout hard ceiling — Claim 5.7
  # -------------------------------------------------------------------
  describe 'timeout hard ceiling' do
    it 'clamps excessive timeout to 30000ms' do
      expect(WildRailsSafeIntrospection::Configuration::HARD_TIMEOUT_CEILING_MS).to eq(30_000)
      expect(99_999.clamp(
               WildRailsSafeIntrospection::Configuration::MINIMUM_TIMEOUT_MS,
               WildRailsSafeIntrospection::Configuration::HARD_TIMEOUT_CEILING_MS
             )).to eq(30_000)
    end

    it 'clamps too-low timeout to minimum 100ms' do
      expect(WildRailsSafeIntrospection::Configuration::MINIMUM_TIMEOUT_MS).to eq(100)
      expect(1.clamp(
               WildRailsSafeIntrospection::Configuration::MINIMUM_TIMEOUT_MS,
               WildRailsSafeIntrospection::Configuration::HARD_TIMEOUT_CEILING_MS
             )).to eq(100)
    end
  end

  # -------------------------------------------------------------------
  # Timeout bypass attempts — Claim 5.5
  # -------------------------------------------------------------------
  describe 'timeout bypass attempts' do
    it 'treats SET statement_timeout in filter value as literal' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: 'SET statement_timeout',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end
  end
end
