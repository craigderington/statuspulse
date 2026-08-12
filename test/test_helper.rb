ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rate limit counters live in Rails.cache, which is :memory_store in test and
    # is shared by every example in a worker process. Without this, any suite
    # that signs the same user in more than five times a minute starts failing
    # with redirects to /login — and the failures look like broken pagination,
    # or broken anything else, rather than a throttle.
    setup { Rails.cache.clear }

    # Two-factor enforcement is off by default in test (see
    # config/environments/test.rb). Wrap an example in this to exercise the
    # mandatory path.
    def with_two_factor_required
      previous = Rails.configuration.x.require_two_factor
      Rails.configuration.x.require_two_factor = true
      yield
    ensure
      Rails.configuration.x.require_two_factor = previous
    end

    # Enrols a user and returns them, for tests that need an account already
    # holding a second factor.
    def enrol_totp!(user)
      user.begin_totp_enrolment!
      user.confirm_totp!(user.totp.now)
      user
    end
  end
end
