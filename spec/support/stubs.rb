CEPH_FSID = '8102bb29-f48b-4f6e-81d7-4c59d80ec6b8'.freeze

shared_context 'common_stubs' do
  before do
    stub_data_bag_item('openstack', 'x86').and_return(openstack_secrets_stub)
    # On the provider itself: a first converge reloads the library over any_instance stubs
    stubs_for_provider('osl_openstack_client') do |provider|
      allow(provider).to receive(:openstack_rdo_installed?).and_return(false)
    end
    # The version guard shells out to rpm; specs assume the package moved
    allow_any_instance_of(Chef::Resource::NotifyGroup).to receive(:openstack_db_sync_needed?).and_return(true)
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/etc/ceph/ceph.conf').and_return("fsid = #{CEPH_FSID}")
  end
end

shared_context 'region2_stubs' do
  before do
    stub_data_bag_item('openstack', 'x86').and_return(region2_secrets)
    # On the provider itself: a first converge reloads the library over any_instance stubs
    stubs_for_provider('osl_openstack_client') do |provider|
      allow(provider).to receive(:openstack_rdo_installed?).and_return(false)
    end
    # The version guard shells out to rpm; specs assume the package moved
    allow_any_instance_of(Chef::Resource::NotifyGroup).to receive(:openstack_db_sync_needed?).and_return(true)
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/etc/ceph/ceph.conf').and_return(nil)
  end
end

shared_context 'dashboard_noregion_stubs' do
  before do
    stub_data_bag_item('openstack', 'x86').and_return(dashboard_noregion_secrets)
    # On the provider itself: a first converge reloads the library over any_instance stubs
    stubs_for_provider('osl_openstack_client') do |provider|
      allow(provider).to receive(:openstack_rdo_installed?).and_return(false)
    end
    # The version guard shells out to rpm; specs assume the package moved
    allow_any_instance_of(Chef::Resource::NotifyGroup).to receive(:openstack_db_sync_needed?).and_return(true)
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/etc/ceph/ceph.conf').and_return(nil)
  end
end

# Guards of the executes osl_openstack_messaging declares when stepped into
shared_context 'rabbitmq_stubs' do
  before do
    {
      'add user openstack' => 'rabbitmqctl -q list_users',
      'set permissions openstack' => 'rabbitmqctl -q list_permissions',
      'set user tags openstack' => 'rabbitmqctl -q list_users',
      'enable plugin rabbitmq_management' => 'rabbitmq-plugins -q list -e -m',
      'enable plugin rabbitmq_prometheus' => 'rabbitmq-plugins -q list -e -m',
    }.each do |name, cmd|
      stubs_for_resource("execute[rabbitmq: #{name}]") do |resource|
        allow(resource).to receive_shell_out(cmd)
      end
    end
  end
end

shared_context 'network_stubs' do
  before do
    stub_command('ip netns exec qdhcp-8df74e06-c4aa-4eb2-b312-0e915bf8f97f iptables -S | egrep "10.0.0.0/24.*port 53.*DROP"')
  end
end

# Keep the keystone probe and modinfo off the network and the host
shared_context 'compute_stubs' do
  before do
    stub_command('virsh net-list | grep -q default').and_return(true)
    stub_command("virsh secret-list | grep #{CEPH_FSID}")
    stub_command("virsh secret-get-value #{CEPH_FSID} | grep AQAjbr1aWv+aNBAAoGfqrwX9iSdNmtuvUkwGhA==")
    allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:openstack_keystone_reachable?).and_return(false)
    allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:kernel_module_available?).and_return(false)
  end
end
