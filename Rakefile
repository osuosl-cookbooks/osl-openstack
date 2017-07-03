current_dir = File.dirname(__FILE__)
client_cfg = "#{current_dir}/test/chef-config"
client_options = '--force-formatter -z ' \
    "--config #{client_cfg}/knife.rb"

task default: ['test']

desc 'Run all tests'
task test: [:style, :lint, :unit]

def run_command(command)
  if File.exist?('Gemfile.lock')
    sh %(bundle exec #{command})
  else
    sh %(chef exec #{command})
  end
end

PROV_PATH = 'test/integration/chef-provisioning'

task :destroy_all do
  Rake::Task[:destroy_machines].invoke
  run_command('rm -rf Gemfile.lock && rm -rf Berksfile.lock && ' \
    'rm -rf cookbooks/')
end

desc 'Destroy machines'
task :destroy_machines do
  run_command("chef-client #{client_options} #{PROV_PATH}/destroy_all.rb")
end

desc 'Vendor your cookbooks/'
task :berks_vendor do
  run_command('rm -rf Berksfile.lock cookbooks/')
  run_command('berks vendor cookbooks')
end

desc 'Create Chef Key'
task :create_key do
  unless File.exist?("#{client_cfg}/validator.pem")
    sh %(chef exec ruby -e "require 'openssl';
File.binwrite('#{client_cfg}/validator.pem',
OpenSSL::PKey::RSA.new(2048).to_pem)")
  end
end

desc 'Controller node'
task controller: [:create_key, :berks_vendor] do
  run_command("chef-client #{client_options} " \
    "#{PROV_PATH}/controller.rb")
end

desc 'Controller node (Separate network node)'
task controller_sep_net: [:create_key, :berks_vendor] do
  ENV['SEPARATE_NETWORK_NODE'] = 'true'
  run_command("chef-client #{client_options} " \
    "#{PROV_PATH}/controller.rb")
end

desc 'Network node'
task network: [:create_key, :berks_vendor] do
  ENV['SEPARATE_NETWORK_NODE'] = 'true'
  run_command("chef-client #{client_options} " \
    "#{PROV_PATH}/network.rb")
end

desc 'Compute node'
task compute: [:create_key, :berks_vendor] do
  run_command("chef-client #{client_options} " \
    "#{PROV_PATH}/compute.rb")
end

desc 'Compute node (Separate network node)'
task compute_sep_net: [:create_key, :berks_vendor] do
  ENV['SEPARATE_NETWORK_NODE'] = 'true'
  run_command("chef-client #{client_options} " \
    "#{PROV_PATH}/compute.rb")
end

desc 'Controller/Compute nodes'
task controller_compute: [:create_key, :berks_vendor, :controller, :compute]

desc 'Controller/Network/Compute nodes'
task controller_network_compute: [:create_key, :berks_vendor, :controller_sep_net, :network, :compute_sep_net]

desc 'Blow everything away'
task clean: [:destroy_all]

# CI tasks
require 'rubocop/rake_task'
desc 'Run RuboCop (style) tests'
RuboCop::RakeTask.new(:style)

desc 'Run FoodCritic (lint) tests'
task :lint do
    run_command('foodcritic --epic-fail any .')
end

desc 'Run RSpec (unit) tests'
task :unit do
    run_command('rm -f Berksfile.lock')
    run_command('rspec --format documentation --color')
end
