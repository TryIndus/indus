class Portfolio < ApplicationRecord
  belongs_to :user
  has_many :positions, dependent: :destroy
  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :user_id }
  validates :base_currency, format: { with: /\A[A-Z]{3}\z/ }
end
