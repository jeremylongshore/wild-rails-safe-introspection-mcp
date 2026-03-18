# frozen_string_literal: true

class Account < ActiveRecord::Base
  has_many :users
  has_many :api_keys
end

class User < ActiveRecord::Base
  belongs_to :account
end

class FeatureFlag < ActiveRecord::Base
end

class CreditCard < ActiveRecord::Base
  belongs_to :user
end

class ApiKey < ActiveRecord::Base
  belongs_to :account
end
