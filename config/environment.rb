# Be sure to restart your web server when you modify this file.

# Uncomment below to force Rails into production mode when 
# you don't control web/app server and can't set it the proper way
# ENV['RAILS_ENV'] ||= 'production'

# Specifies gem version of Rails to use when vendor/rails is not present
RAILS_GEM_VERSION = '1.2.6' unless defined? RAILS_GEM_VERSION

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')
require 'lib/conf'
require 'uri'

Rails::Initializer.run do |config|
  # Settings in config/environments/* take precedence over those specified here
  
  # Skip frameworks you're not going to use (only works if using vendor/rails)
  # config.frameworks -= [ :action_web_service, :action_mailer ]

  # Only load the plugins named here, by default all plugins in vendor/plugins are loaded
  # config.plugins = %W( exception_notification ssl_requirement )

  config.plugins = ["engines", "encrypted_strings", "widgets", "white_list", "white_list_formatted_content", "*"]

  # Add additional load paths for your own custom dirs
  # config.load_paths += %W( #{RAILS_ROOT}/extras )

  # Force all environments to use the same logger level 
  # (by default production uses :info, the others :debug)
  # config.log_level = :debug

  # Use the database for sessions instead of the file system
  # (create the session table with 'rake db:sessions:create')

  config.action_controller.session_store = :active_record_store

  # Use SQL instead of Active Record's schema dumper when creating the test database.
  # This is necessary if your schema can't be completely dumped by the schema dumper, 
  # like if you have constraints or database-specific column types
  # config.active_record.schema_format = :sql

  # Activate observers that should always be running
  # config.active_record.observers = :cacher, :garbage_collector

  # Make Active Record use UTC-base instead of local time
  # config.active_record.default_timezone = :utc
  
  # See Rails::Configuration for more options

  base_uri = URI.parse(Conf.base_uri)

  config.action_mailer.default_url_options = {
    :host => base_uri.host + (base_uri.port == 80 ? "" : ":#{base_uri.port.to_s}")
  }

end

# Add new inflection rules using the following format 
# (all these examples are active by default):
# Inflector.inflections do |inflect|
#   inflect.plural /^(ox)$/i, '\1en'
#   inflect.singular /^(ox)en/i, '\1'
#   inflect.irregular 'person', 'people'
#   inflect.uncountable %w( fish sheep )
# end

# Add new mime types for use in respond_to blocks:
# Mime::Type.register "text/richtext", :rtf
# Mime::Type.register "application/x-mobile", :mobile

Mime::Type.register "application/whip-archive", :whip
Mime::Type.register "application/rdf+xml", :rdf

# Include your application configuration below

require 'lib/conf'

# SMTP configuration

require 'smtp_tls'
require 'authorization'

ActionMailer::Base.smtp_settings = Conf.smtp

# don't require actual keys for recaptcha during tests

if RAILS_ENV == 'test'
  Recaptcha.configure do |config|
    config.public_key  = ''
    config.private_key = ''
  end
end

class ActiveRecord::Base

  def inhibit_timestamps(&blk)

    initial_value = ActiveRecord::Base.record_timestamps

    begin
      ActiveRecord::Base.record_timestamps = false
      yield
    rescue Exception
      ActiveRecord::Base.record_timestamps = initial_value
      raise
    end

    ActiveRecord::Base.record_timestamps = initial_value
  end
end

load 'config/environment_private.rb' if FileTest.exist?('config/environment_private.rb')

module ActionView
  module Helpers
    module TextHelper
      def truncate(text, length = 30, truncate_string = "...")
        if text.nil? then return end
        l = length - truncate_string.chars.to_a.size
        (text.chars.to_a.size > length ? text.chars.to_a[0...l].join + truncate_string : text).to_s
      end
    end
  end
end
