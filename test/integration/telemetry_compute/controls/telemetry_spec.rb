control 'telemetry-compute' do
  describe package 'openstack-ceilometer-compute' do
    it { should be_installed }
  end

  describe service 'openstack-ceilometer-compute' do
    it { should be_enabled }
    it { should be_running }
  end
end
