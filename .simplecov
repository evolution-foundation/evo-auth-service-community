SimpleCov.start 'rails' do
  # Coverage thresholds
  minimum_coverage 85
  minimum_coverage_by_file 70

  # Groups for better organization
  add_group 'Models', 'app/models'
  add_group 'Controllers', 'app/controllers'
  add_group 'Services', 'app/services'
  add_group 'Builders', 'app/builders'
  add_group 'Concerns', 'app/models/concerns'
  add_group 'Helpers', 'app/helpers'
  add_group 'Jobs', 'app/jobs'
  add_group 'Listeners', 'app/listeners'
  add_group 'Policies', 'app/policies'
  add_group 'Lib', 'lib'

  # Files to exclude from coverage
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/db/'
  add_filter '/bin/'
  add_filter '/log/'
  add_filter '/tmp/'
  add_filter '/public/'
  add_filter 'app/channels/application_cable/'
  add_filter 'app/jobs/application_job.rb'
  add_filter 'app/mailers/application_mailer.rb'
  add_filter 'app/models/application_record.rb'
  add_filter 'app/controllers/application_controller.rb'

  # Track files even if they're not loaded during tests
  track_files '{app,lib}/**/*.rb'

  # Merge results from different test runs
  merge_timeout 3600

  # Format configuration
  if ENV['CI']
    require 'simplecov-lcov'
    SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
    formatter SimpleCov::Formatter::LcovFormatter
  else
    require 'simplecov-lcov'
    SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
    formatters = [
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::LcovFormatter
    ]
    formatter SimpleCov::Formatter::MultiFormatter.new(formatters)
  end
end
