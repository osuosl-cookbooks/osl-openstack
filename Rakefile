current_dir = File.dirname(__FILE__)
client_cfg = "#{current_dir}/test/chef-config"

require 'rake'
require 'fileutils'
require 'base64'
require 'chef/encrypted_data_bag_item'
require 'json'
require 'openssl'

snakeoil_file_path = 'test/integration/data_bags/certificates/snakeoil.json'
encrypted_data_bag_secret_path = 'test/integration/encrypted_data_bag_secret'

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

##
# Create a self-signed SSL certificate
#
def gen_ssl_cert
  name = OpenSSL::X509::Name.new [
    %w(C US),
    %w(ST Oregon),
    ['CN', 'controller.example.com'],
    %w(DC example),
  ]
  key = OpenSSL::PKey::RSA.new 2048

  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = 2
  cert.subject = name
  cert.public_key = key.public_key
  cert.not_before = Time.now
  cert.not_after = cert.not_before + 1 * 365 * 24 * 60 * 60 # 1 years validity

  # Self-sign the Certificate
  cert.issuer = name
  cert.sign(key, OpenSSL::Digest.new('SHA1'))

  [cert, key]
end

##
# Create a data bag item (with the id of snakeoil) containing a self-signed SSL
#  certificate
#
def ssl_data_bag_item
  cert, key = gen_ssl_cert
  Chef::DataBagItem.from_hash(
    'id' => 'snakeoil',
    'cert' => cert.to_pem,
    'key' => key.to_pem
  )
end

##
# Create the encrypted snakeoil certificate under
#  test/integration/data_bags/certificates
#
file snakeoil_file_path => [
  'test/integration/data_bags/certificates',
  'test/integration/encrypted_data_bag_secret',
] do
  encrypted_data_bag_secret = Chef::EncryptedDataBagItem.load_secret(
    encrypted_data_bag_secret_path
  )

  encrypted_snakeoil_cert = Chef::EncryptedDataBagItem.encrypt_data_bag_item(
    ssl_data_bag_item, encrypted_data_bag_secret
  )

  open snakeoil_file_path, 'w' do |io|
    io.write JSON.pretty_generate(encrypted_snakeoil_cert)
  end
end

task :destroy_all do
  run_command('rm -rf Gemfile.lock && rm -rf Berksfile.lock && rm -rf cookbooks/')
end

desc 'Create an Encrypted Databag Snakeoil SSL Certificate'
task snakeoil: snakeoil_file_path

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
