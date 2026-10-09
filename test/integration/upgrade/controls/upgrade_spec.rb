# The bag targets zed on a yoga node: Chef stages zed and installs none of it
control 'upgrade-staging' do
  describe command("rpm -q --whatprovides 'osuosl-openstack-release(yoga)'") do
    its('exit_status') { should eq 0 }
  end

  describe command("rpm -q --whatprovides 'osuosl-openstack-release(zed)'") do
    its('exit_status') { should_not eq 0 }
  end

  describe yum.repo('OSL-openstack') do
    it { should be_enabled }
    its('baseurl') { should include '/openstack/yoga/' }
  end

  describe yum.repo('OSL-openstack-zed') do
    it { should exist }
    it { should_not be_enabled }
  end

  describe file('/var/lib/osl-openstack/staged-zed') do
    it { should exist }
  end

  describe command("find /var/cache/dnf -path '*OSL-openstack-zed*' -name 'osuosl-openstack-keystone-*.rpm'") do
    its('stdout') { should match /osuosl-openstack-keystone-22\./ }
  end

  describe json('/etc/osl-openstack/release.json') do
    its('installed') { should eq 'yoga' }
    its('target') { should eq 'zed' }
    its('staged') { should eq true }
  end

  describe service('keystone-uwsgi') do
    it { should be_running }
  end
end
