# frozen_string_literal: true

# Adversarial tests for access control bypass attempts.
#
# Safety claims covered: 2.5, 2.8, 2.9, 3.8, 2.6-adv, 2.7-adv
# These tests verify that allowlist and denylist controls cannot be bypassed
# via case variations, encoding tricks, or information leakage.
RSpec.describe 'Access Control Adversarial', :adversarial, :safety do
  include TestConfigHelper

  before do
    configure_with_test_fixtures!
    User.delete_all
    Account.delete_all
    FeatureFlag.delete_all
    Account.create!(
      name: 'Acme Corp', slug: 'acme', plan: 'pro',
      stripe_customer_id: 'cus_secret123', tax_id: 'tax_secret456', ssn: '999-99-9999'
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
  # Allowlist bypass via model name case variations — Claim 2.5
  # -------------------------------------------------------------------
  describe 'allowlist bypass via model name variations' do
    %w[account ACCOUNT aCcOuNt aCCOUNT].each do |variant|
      it "denies case variation #{variant.inspect}" do
        response = tool_schema.call(model_name: variant, server_context: ctx)
        parsed = parse_response(response)

        expect(response.error?).to be(true)
        expect(parsed[:status]).to eq('denied')
      end
    end

    it 'produces identical denial shape for all case variations' do
      variants = %w[account ACCOUNT aCcOuNt]
      responses = variants.map do |v|
        parse_response(tool_schema.call(model_name: v, server_context: ctx))
      end

      responses.each_cons(2) do |a, b|
        expect(a.keys.sort).to eq(b.keys.sort)
        expect(a[:status]).to eq(b[:status])
        expect(a[:reason]).to eq(b[:reason])
      end
    end
  end

  # -------------------------------------------------------------------
  # Allowlist bypass via encoding and namespace tricks — Claim 2.8
  # -------------------------------------------------------------------
  describe 'allowlist bypass via encoding/namespace tricks' do
    [
      '::Account',
      'Module::Account',
      ' Account',
      'Account ',
      "Account\n",
      "Account\0"
    ].each do |variant|
      it "denies encoding trick #{variant.inspect}" do
        response = tool_schema.call(model_name: variant, server_context: ctx)
        parsed = parse_response(response)

        expect(response.error?).to be(true)
        expect(parsed[:status]).to eq('denied')
      end
    end
  end

  # -------------------------------------------------------------------
  # Denylist column exfiltration attempts — Claim 2.9, 3.8
  # -------------------------------------------------------------------
  describe 'denylist column exfiltration attempts' do
    it 'raw JSON never contains blocked column names in lookup response' do
      account = Account.first
      response = tool_lookup.call(model_name: 'Account', id: account.id.to_s, server_context: ctx)
      raw_text = response.content.first[:text]

      %w[stripe_customer_id tax_id ssn].each do |col|
        expect(raw_text).not_to include(col)
      end
    end

    it 'raw JSON never contains blocked column values in lookup response' do
      account = Account.first
      response = tool_lookup.call(model_name: 'Account', id: account.id.to_s, server_context: ctx)
      raw_text = response.content.first[:text]

      %w[cus_secret123 tax_secret456 999-99-9999].each do |val|
        expect(raw_text).not_to include(val)
      end
    end

    it 'filtering on non-blocked field still strips blocked columns from results' do
      response = tool_filter.call(
        model_name: 'Account', field: 'slug', value: 'acme', server_context: ctx
      )
      parsed = parse_response(response)

      parsed[:records].each do |record|
        expect(record.keys.map(&:to_s) & %w[stripe_customer_id tax_id ssn]).to be_empty
      end
    end

    it 'schema inspection strips blocked columns from column list' do
      response = tool_schema.call(model_name: 'Account', server_context: ctx)
      col_names = parse_response(response)[:columns].map { |c| c[:name] }

      %w[stripe_customer_id tax_id ssn].each do |col|
        expect(col_names).not_to include(col)
      end
    end
  end

  # -------------------------------------------------------------------
  # Information leakage via denial analysis — Claim 2.6-adv, 2.7-adv
  # -------------------------------------------------------------------
  describe 'information leakage via denial analysis' do
    it 'denial for blocked model is identical to denial for unknown model' do
      blocked = parse_response(tool_schema.call(model_name: 'CreditCard', server_context: ctx))
      unknown = parse_response(tool_schema.call(model_name: 'NonExistentModel', server_context: ctx))

      expect(blocked.keys.sort).to eq(unknown.keys.sort)
      expect(blocked[:status]).to eq(unknown[:status])
      expect(blocked[:reason]).to eq(unknown[:reason])
      expect(blocked[:message]).to eq(unknown[:message])
    end

    it 'denial message never contains the requested model name' do
      %w[CreditCard ApiKey NonExistentModel].each do |model|
        parsed = parse_response(tool_schema.call(model_name: model, server_context: ctx))
        raw_text = tool_schema.call(model_name: model, server_context: ctx).content.first[:text]

        expect(raw_text).not_to include(model)
        expect(parsed[:message]).not_to include(model)
      end
    end

    it 'filter denial for blocked field is identical to filter denial for nonexistent field' do
      blocked = parse_response(tool_filter.call(
                                 model_name: 'Account', field: 'stripe_customer_id', value: 'x',
                                 server_context: ctx
                               ))
      nonexistent = parse_response(tool_filter.call(
                                     model_name: 'Account', field: 'totally_fake_field', value: 'x',
                                     server_context: ctx
                                   ))

      expect(blocked[:status]).to eq(nonexistent[:status])
      expect(blocked[:reason]).to eq(nonexistent[:reason])
    end
  end

  # -------------------------------------------------------------------
  # Runtime configuration immutability — Claim 2.5
  # -------------------------------------------------------------------
  describe 'runtime configuration immutability' do
    let(:config) { WildRailsSafeIntrospection.configuration }

    it 'model_registry is frozen' do
      expect(config.model_registry).to be_frozen
      expect { config.model_registry['Evil'] = { klass: Object } }.to raise_error(FrozenError)
    end

    it 'blocked_models is frozen' do
      expect(config.blocked_models).to be_frozen
      expect { config.blocked_models << 'Evil' }.to raise_error(FrozenError)
    end

    it 'blocked_columns is frozen' do
      expect(config.blocked_columns).to be_frozen
      expect { config.blocked_columns << { 'model' => '*', 'columns' => ['evil'] } }.to raise_error(FrozenError)
    end

    it 'defaults is frozen' do
      expect(config.defaults).to be_frozen
      expect { config.defaults['max_rows'] = 999_999 }.to raise_error(FrozenError)
    end
  end
end
