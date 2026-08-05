class Report < ApplicationRecord
  STATUSES = %w[queued generating completed failed cancelled].freeze
  belongs_to :user
  has_many :report_sources, dependent: :destroy
  before_validation { self.symbol = symbol.to_s.upcase.strip }
  validates :symbol, format: { with: /\A[A-Z0-9.\/-]{1,20}\z/ }
  validates :status, inclusion: { in: STATUSES }
  validates :title, presence: true, length: { maximum: 200 }
end
