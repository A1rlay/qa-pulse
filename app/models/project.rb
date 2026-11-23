class Project < ApplicationRecord
  has_many :runs, dependent: :restrict_with_error

  before_validation :assign_slug, on: :create
  before_validation :assign_api_token, on: :create

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true, uniqueness: true, length: { maximum: 100 },
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :api_token, presence: true, uniqueness: true

  def to_param = slug

  # Timing-safe check of an upload's bearer token against this project's token.
  def valid_token?(candidate)
    candidate.present? && ActiveSupport::SecurityUtils.secure_compare(api_token, candidate.to_s)
  end

  def latest_run = runs.order(started_at: :desc, id: :desc).first

  def recent_runs(limit, branch: nil)
    scope = runs.order(started_at: :desc, id: :desc).limit(limit)
    branch.present? ? scope.where(branch: branch) : scope
  end

  def branches = runs.where.not(branch: [ nil, "" ]).distinct.order(:branch).pluck(:branch)

  # Genera un token nuevo; el anterior deja de funcionar de inmediato.
  def rotate_api_token!
    update!(api_token: SecureRandom.hex(32))
  end

  private

  def assign_slug
    return if slug.present? || name.blank?
    base = name.parameterize.presence || "proyecto"
    candidate = base
    n = 2
    while Project.exists?(slug: candidate)
      candidate = "#{base}-#{n}"
      n += 1
    end
    self.slug = candidate
  end

  def assign_api_token
    self.api_token ||= SecureRandom.hex(32)
  end
end
