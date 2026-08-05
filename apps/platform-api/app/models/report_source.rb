class ReportSource < ApplicationRecord
  belongs_to :report
  validates :provider, :kind, :source_reference, presence: true
end
