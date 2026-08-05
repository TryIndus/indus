class Position < ApplicationRecord
  belongs_to :portfolio
  before_validation { self.symbol = symbol.to_s.upcase.strip }
  validates :symbol, format: { with: /\A[A-Z0-9.\/-]{1,20}\z/ }, uniqueness: { scope: %i[portfolio_id instrument_type] }
  validates :quantity, numericality: { greater_than: 0 }
  validates :average_cost, numericality: { greater_than_or_equal_to: 0 }
  validates :instrument_type, inclusion: { in: %w[equity crypto] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
end
