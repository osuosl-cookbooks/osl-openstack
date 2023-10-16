current_dir = File.dirname(__FILE__)
client_cfg = "#{current_dir}/test/chef-config"

task default: ['test']

desc 'Run all tests'
task test: [:style, :unit]

def run_command(command)
  if File.exist?('Gemfile.lock')
    sh %(bundle exec #{command})
  else
    sh %(cinc exec #{command})
  end
end

task :destroy_all do
  run_command('rm -rf Gemfile.lock && rm -rf Berksfile.lock && rm -rf cookbooks/')
end

desc 'Vendor your cookbooks/'
task berks_vendor: :clean do
  run_command('berks vendor cookbooks')
end

desc 'Upload data to chef-zero server'
task knife_upload: :berks_vendor do
  run_command('knife upload . --force -c test/chef-config/knife.rb')
end

desc 'Create Chef Key'
task :create_key do
  unless File.exist?("#{client_cfg}/validator.pem")
    File.binwrite("#{client_cfg}/validator.pem", OpenSSL::PKey::RSA.new(2048).to_pem)
  end
  unless File.exist?("#{client_cfg}/fakeclient.pem")
    File.binwrite("#{client_cfg}/fakeclient.pem", OpenSSL::PKey::RSA.new(2048).to_pem)
  end
end

desc 'Blow everything away'
task clean: [:destroy_all]

# CI tasks
require 'cookstyle'
require 'rubocop/rake_task'
desc 'Run RuboCop (cookstyle) tests'
RuboCop::RakeTask.new(:style) do |task|
  task.options << '--display-cop-names'
end

desc 'Run RSpec (unit) tests'
task :unit do
  run_command('rm -f Berksfile.lock')
  run_command('rspec --format documentation --color')
end
