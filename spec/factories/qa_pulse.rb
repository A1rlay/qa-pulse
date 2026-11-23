FactoryBot.define do
  factory :project do
    sequence(:name) { |n| "Proyecto #{n}" }
  end

  factory :run do
    project
    branch { "main" }
    sequence(:started_at) { |n| Time.utc(2026, 1, 1) + n.hours }
  end

  factory :test_result do
    run
    file { "carrito.spec.ts" }
    title { "Carrito > agrega un producto" }
    project_name { "chromium" }
    status { "passed" }
    duration_ms { 100 }
    retries { 0 }
  end
end
