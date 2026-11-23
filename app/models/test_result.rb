require "digest"

class TestResult < ApplicationRecord
  STATUSES = %w[passed failed skipped flaky].freeze

  belongs_to :run

  before_validation :assign_test_key

  validates :file, presence: true, length: { maximum: 500 }
  validates :title, presence: true
  validates :project_name, length: { maximum: 100 }
  validates :status, inclusion: { in: STATUSES }
  validates :duration_ms, :retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Identity of a test across runs: file + full title path + Playwright project.
  def self.key_for(file, title, project_name)
    Digest::SHA256.hexdigest([ file, title, project_name.to_s ].join("\u0000"))
  end

  private

  def assign_test_key
    self.test_key = self.class.key_for(file, title, project_name) if file && title
  end
end
