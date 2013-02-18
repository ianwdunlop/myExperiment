# Be sure to restart your server when you modify this file

# Specifies gem version of Rails to use when vendor/rails is not present
RAILS_GEM_VERSION = '2.3.17' unless defined? RAILS_GEM_VERSION

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')
require 'lib/conf'
require 'uri'

Rails::Initializer.run do |config|
  # Settings in config/environments/* take precedence over those specified here.
  # Application configuration should go into files in config/initializers
  # -- all .rb files in that directory are automatically loaded.

  # Add additional load paths for your own custom dirs
  # config.autoload_paths += %W( #{RAILS_ROOT}/extras )

  # Specify gems that this application depends on and have them installed with rake gems:install
  # config.gem "bj"
  # config.gem "hpricot", :version => '0.6', :source => "http://code.whytheluckystiff.net"
  # config.gem "sqlite3-ruby", :lib => "sqlite3"
  # config.gem "aws-s3", :lib => "aws/s3"

  # Only load the plugins named here, in the order given (default is alphabetical).
  # :all can be used as a placeholder for all plugins not explicitly named
  # config.plugins = [ :exception_notification, :ssl_requirement, :all ]
  config.plugins = [
    :widgets,
    :country_select,
    :white_list,
    :white_list_formatted_content,
    :acts_as_bookmarkable,
    :acts_as_commentable,
    :acts_as_rateable,
    :acts_as_solr,
    :acts_as_taggable_redux,
    :auto_complete,
    :headliner,
    :oauth,
    :oauth_plugin,
    :open_id_authentication,
    :paginating_find,
    :simile_timeline,
    :validates_email_veracity_of,
    :versioning,
  ]

  # Skip frameworks you're not going to use. To use Rails without a database,
  # you must remove the Active Record framework.
  # config.frameworks -= [ :active_record, :active_resource, :action_mailer ]

  # Activate observers that should always be running
  # config.active_record.observers = :cacher, :garbage_collector, :forum_observer

  # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
  # Run "rake -D time" for a list of tasks for finding time zone names.
  config.time_zone = 'UTC'

  # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
  # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}')]
  # config.i18n.default_locale = :de
end

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

