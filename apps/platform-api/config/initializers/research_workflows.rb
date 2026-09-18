# Temporal activities remain available for a future worker but are not loaded by the Sidekiq runtime.
activities_path = Rails.root.join("app/services/reports/research_activities.rb")
Rails.autoloaders.main.ignore(activities_path)
