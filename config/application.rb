require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RailsProject1
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Whether every account must hold a second factor. Shipped as a switch
    # rather than a constant so it can be turned on only once an operator has
    # enrolled successfully — a bug in enrolment with this hard-coded true locks
    # out every user, including the one who would fix it. Defaults on; set
    # REQUIRE_2FA=false to disable.
    config.x.require_two_factor = ENV.fetch("REQUIRE_2FA", "true") != "false"

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
