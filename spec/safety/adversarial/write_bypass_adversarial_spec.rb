# frozen_string_literal: true

# Adversarial tests for write bypass and code execution prevention.
#
# Safety claims covered: 1.4, 8.2, 8.6, 8.7, 8.8, 8.10, 1.11-edge
# These tests verify that no user-supplied input can trigger dynamic dispatch,
# SQL injection, or arbitrary code execution.
RSpec.describe 'Write Bypass Adversarial', :adversarial, :safety do
  include TestConfigHelper

  before do
    configure_with_test_fixtures!
    User.delete_all
    Account.delete_all
    FeatureFlag.delete_all
    Account.create!(
      name: 'Acme Corp', slug: 'acme', plan: 'pro',
      stripe_customer_id: 'cus_secret', tax_id: 'tax_secret', ssn: '999-99-9999'
    )
  end

  let(:ctx) { authenticated_server_context }
  let(:tool_schema) { WildRailsSafeIntrospection::Server::Tools::InspectModelSchema }
  let(:tool_lookup) { WildRailsSafeIntrospection::Server::Tools::LookupRecordById }
  let(:tool_filter) { WildRailsSafeIntrospection::Server::Tools::FindRecordsByFilter }

  def parse_response(response)
    JSON.parse(response.content.first[:text], symbolize_names: true)
  end

  # -------------------------------------------------------------------
  # Dynamic dispatch prevention — Claim 8.2, 8.6
  # -------------------------------------------------------------------
  describe 'dynamic dispatch prevention' do
    it 'denies model_name payload "Account.destroy_all"' do
      response = tool_schema.call(model_name: 'Account.destroy_all', server_context: ctx)
      parsed = parse_response(response)

      expect(response.error?).to be(true)
      expect(parsed[:status]).to eq('denied')
    end

    it 'denies model_name payload "eval(\'exit\')"' do
      response = tool_schema.call(model_name: "eval('exit')", server_context: ctx)
      parsed = parse_response(response)

      expect(response.error?).to be(true)
      expect(parsed[:status]).to eq('denied')
    end

    it 'treats id containing Ruby code as opaque string' do
      response = tool_lookup.call(model_name: 'Account', id: 'system("rm -rf /")', server_context: ctx)
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('not_found')
    end

    it 'treats filter value containing Ruby code as opaque string' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: 'Kernel.exec("id")',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end

    it 'denies field parameter "__send__"' do
      response = tool_filter.call(
        model_name: 'Account', field: '__send__', value: 'destroy_all',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(response.error?).to be(true)
      expect(parsed[:status]).to eq('denied')
    end

    it 'denies field parameter "instance_eval"' do
      response = tool_filter.call(
        model_name: 'Account', field: 'instance_eval', value: 'malicious',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(response.error?).to be(true)
      expect(parsed[:status]).to eq('denied')
    end
  end

  # -------------------------------------------------------------------
  # SQL injection via tool parameters — Claim 8.7, 8.8
  # -------------------------------------------------------------------
  describe 'SQL injection via tool parameters' do
    it 'treats SQL DROP as literal filter value' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: "'; DROP TABLE users; --",
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end

    it 'treats OR tautology as literal filter value' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: "' OR '1'='1",
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end

    it 'treats UNION SELECT as literal filter value' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: "' UNION SELECT * FROM users --",
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end

    it 'treats INSERT injection in id as not_found' do
      response = tool_lookup.call(
        model_name: 'Account', id: '1; INSERT INTO users VALUES(99)',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('not_found')
    end

    it 'treats SQL comment injection as literal filter value' do
      response = tool_filter.call(
        model_name: 'Account', field: 'name', value: 'value /* */ OR 1=1',
        server_context: ctx
      )
      parsed = parse_response(response)

      expect(parsed[:status]).to eq('ok')
      expect(parsed[:records]).to be_empty
    end
  end

  # -------------------------------------------------------------------
  # Code execution via model_name — Claim 8.10, 1.4
  # -------------------------------------------------------------------
  describe 'code execution via model_name' do
    %w[Object Kernel File BasicObject Module Class].each do |dangerous_const|
      it "denies dangerous constant #{dangerous_const}" do
        response = tool_schema.call(model_name: dangerous_const, server_context: ctx)
        parsed = parse_response(response)

        expect(response.error?).to be(true)
        expect(parsed[:status]).to eq('denied')
      end
    end

    it 'denies global prefix "::Account"' do
      response = tool_schema.call(model_name: '::Account', server_context: ctx)
      parsed = parse_response(response)

      expect(response.error?).to be(true)
      expect(parsed[:status]).to eq('denied')
    end

    it 'denies null byte injection "Account\x00evil"' do
      response = tool_schema.call(model_name: "Account\x00evil", server_context: ctx)
      parsed = parse_response(response)

      expect(response.error?).to be(true)
      expect(parsed[:status]).to eq('denied')
    end
  end
end
