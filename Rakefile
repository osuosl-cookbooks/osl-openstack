current_dir = File.dirname(__FILE__)
client_cfg = "#{current_dir}/test/chef-config"
client_options = '--force-formatter -z ' \
    "--config #{client_cfg}/knife.rb"

task default: ['test']

desc 'Default gate tests to run'
task test: [:rubocop, :berks_vendor]

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

desc 'Controller/Compute nodes'
task controller_compute: [:create_key, :berks_vendor] do
  run_command("chef-client #{client_options} " \
    "#{PROV_PATH}/controller_compute.rb")
end

desc 'Blow everything away'
task clean: [:destroy_all]

# CI tasks
require 'rubocop/rake_task'
desc 'Run RuboCop'
RuboCop::RakeTask.new(:rubocop)

desc 'Run FoodCritic (lint) tests'
task :lint do
    run_command('foodcritic --epic-fail any .')
end

desc 'Run RSpec (unit) tests'
task :unit do
    run_command('rspec --format documentation --color')
end
