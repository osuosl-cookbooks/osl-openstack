require 'chefspec'
require 'chefspec/berkshelf'
require_relative '../libraries/helpers'

Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }

# The helpers cache the data bag at module level; reset it per example
RSpec.configure do |config|
  config.before(:each) do
    OSLOpenstack::Cookbook::Helpers.reset_cache! if defined?(OSLOpenstack::Cookbook::Helpers)
  end
end

ALMA_9 = {
  platform: 'almalinux',
  version: '9',
  file_cache_path: '/var/chef/cache',
  log_level: :warn,
}.freeze

# Only the messaging tier recipes run on EL10, so it stays out of ALL_PLATFORMS
ALMA_10 = {
  platform: 'almalinux',
  version: '10',
  file_cache_path: '/var/chef/cache',
  log_level: :warn,
}.freeze

ALL_PLATFORMS = [
  ALMA_9,
].freeze
