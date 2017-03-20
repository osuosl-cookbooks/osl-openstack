require 'serverspec'

set :backend, :exec

describe service('neutron-mlnx-agent') do
  it { should be_enabled }
  it { should be_running }
end

# It should be running however it will fail due to the lack of real Mellanox hardware in TK
describe service('eswitchd') do
  it { should be_enabled }
end

[
  %r{^url = https://localhost/neo/$},
  /^username = admin/,
  /^password = 123456/,
  /^domain = cloudx$/
].each do |line|
  describe file('/etc/neutron/plugin.ini') do
    its(:content) { should match(line) }
  end
end

[
  %r{^daemon_endpoint = tcp://127.0.0.1:60001$},
  /^request_timeout = 3000$/,
  /^retries = 3$/,
  /^backoff_rate = 2$/
].each do |line|
  describe file('/etc/neutron/plugins/mlnx/mlnx_conf.ini') do
    its(:content) { should match(line) }
  end
end

[
  /^fabrics = default:autoeth$/
].each do |line|
  describe file('/etc/neutron/plugins/ml2/eswitchd.conf') do
    its(:content) { should match(line) }
  end
end
