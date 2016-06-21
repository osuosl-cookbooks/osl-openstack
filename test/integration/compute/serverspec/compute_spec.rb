require 'serverspec'

set :backend, :exec

%w(
  openstack-nova-compute
  openstack-ceilometer-compute
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

describe kernel_module('tun') do
  it { should be_loaded }
end
