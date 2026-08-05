class Position < ApplicationRecord
  MAX_PER_PORTFOLIO = 1_000
  belongs_to :portfolio
  before_validation { self.symbol = symbol.to_s.upcase.strip }
  validates :symbol, length: { maximum: 20 }, format: { with: /\A[A-Z0-9]+(?:[.\/-][A-Z0-9]+)?\z/ },
    uniqueness: { scope: %i[portfolio_id instrument_type] }
  validates :quantity, numericality: { greater_than: 0 }
  validates :average_cost, numericality: { greater_than_or_equal_to: 0 }
  validates :instrument_type, inclusion: { in: %w[equity crypto] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validate :portfolio_capacity, on: :create

  private

  def portfolio_capacity
    return unless portfolio_id

    Portfolio.lock.find(portfolio_id)
    errors.add(:base, "portfolio position limit reached") if Position.where(portfolio_id: portfolio_id).count >= MAX_PER_PORTFOLIO
  end
end
