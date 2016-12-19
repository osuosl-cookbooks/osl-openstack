require 'chefspec'
require 'chefspec/berkshelf'
require_relative 'support/matchers'

ChefSpec::Coverage.start! { add_filter 'osl-openstack' }

REDHAT_OPTS = {
  platform: 'centos',
  version: '7.2.1511',
  log_level: :fatal
}.freeze

shared_context 'common_stubs' do
  before do
    node.set['osl-openstack']['endpoint_hostname'] = '10.0.0.10'
    node.set['osl-openstack']['db_hostname'] = '10.0.0.10'
    node.set['osl-openstack']['database_suffix'] = 'x86'
    node.set['osl-openstack']['databag_suffix'] = 'x86'
  end
end

shared_context 'linuxbridge_stubs' do
  before do
    node.set['osl-openstack']['physical_interface_mappings'] =
      [
        name: 'public',
        controller: {
          default: 'eth2'
        },
        compute: {
          default: 'eth1'
        }
      ]
  end
end

shared_context 'identity_stubs' do
  before do
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_servers)
      .and_return('rabbit_servers_value')
    allow_any_instance_of(Chef::Recipe).to receive(:memcached_servers)
      .and_return([])
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', anything)
      .and_return('keystone_db_pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', anything)
      .and_return('')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'guest')
      .and_return('guest')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'user1')
      .and_return('secret1')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return('bootstrap-token')
    stub_command('/usr/sbin/httpd -t')
    allow_any_instance_of(Chef::Recipe).to receive(:search_for)
      .with('os-identity').and_return(
        [{
          'openstack' => {
            'identity' => {
              'admin_tenant_name' => 'admin',
              'admin_user' => 'admin'
            }
          }
        }]
      )
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin')
      .and_return('admin')
  end
end

shared_context 'image_stubs' do
  before do
    allow_any_instance_of(Chef::Recipe).to receive(:address_for)
      .with('lo')
      .and_return('127.0.1.1')
    allow_any_instance_of(Chef::Recipe).to receive(:config_by_role)
      .with('rabbitmq-server', 'queue')
      .and_return(
        'host' => 'rabbit-host', 'port' => 'rabbit-port'
      )
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_servers)
      .and_return '1.1.1.1:5672,2.2.2.2:5672'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return('bootstrap-token')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_vmware_secret_name')
      .and_return 'vmware_secret_name'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', 'glance')
      .and_return('db-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-image')
      .and_return('glance-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'guest')
      .and_return('mq-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin')
      .and_return('admin-pass')
  end
end

shared_context 'network_stubs' do
  before do
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return('bootstrap-token')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'neutron_metadata_secret')
      .and_return('metadata-secret')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', anything)
      .and_return('neutron')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-network')
      .and_return('neutron-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'guest')
      .and_return('mq-pass')
    allow(Chef::Application).to receive(:fatal!)
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-compute')
      .and_return('nova-pass')
  end
  shared_examples 'custom template banner displayer' do
    it 'shows the custom banner' do
      node.set['openstack']['network']['custom_template_banner'] =
        'custom_template_banner_value'
      expect(chef_run).to render_file(file_name)
        .with_content(/^custom_template_banner_value$/)
    end
  end
  shared_examples 'common network attributes displayer' do |plugin|
    it 'displays the interface_driver common attribute' do
      node.set['openstack']["network_#{plugin}"]['conf']['DEFAULT'] \
        ['interface_driver'] = 'network_interface_driver_value'
      expect(chef_run).to render_file(file_name)
        .with_content(/^interface_driver = network_interface_driver_value$/)
    end
  end

  shared_examples 'dhcp agent template configurator' do
    it_behaves_like 'custom template banner displayer'

    it_behaves_like 'common network attributes displayer', 'dhcp'

    %w(resync_interval ovs_use_veth enable_isolated_metadata
       enable_metadata_network dnsmasq_lease_max
       dhcp_delete_namespaces).each do |attr|
      it "displays the #{attr} dhcp attribute" do
        node.set['openstack']['network_dhcp']['conf']['DEFAULT'][attr] =
          "network_dhcp_#{attr}_value"
        expect(chef_run).to render_file(file_name)
          .with_content(/^#{attr} = network_dhcp_#{attr}_value$/)
      end
    end
  end
end

shared_context 'compute_stubs' do
  before do
    node.set['osl-openstack']['nova_public_key'] = 'ssh public key'
    stub_data_bag_item('_secrets', 'nova_migration_key')
      .and_return(nova_migration_key: 'private ssh key')
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_servers)
      .and_return '1.1.1.1:5672,2.2.2.2:5672'
    allow_any_instance_of(Chef::Recipe).to receive(:address_for)
      .with('lo')
      .and_return '127.0.1.1'
    allow_any_instance_of(Chef::Recipe).to receive(:search_for)
      .with('os-identity').and_return(
        [{
          'openstack' => {
            'identity' => {
              'admin_tenant_name' => 'admin',
              'admin_user' => 'admin'
            }
          }
        }]
      )
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return('bootstrap-token')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'neutron_metadata_secret')
      .and_return('metadata-secret')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', 'nova')
      .and_return('nova_db_pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', 'nova_api')
      .and_return('nova_api_db_pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'guest')
      .and_return('mq-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin')
      .and_return('admin')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-compute')
      .and_return('nova-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-network')
      .and_return('neutron-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'rbd_block_storage')
      .and_return 'cinder-rbd-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:memcached_servers)
      .and_return []
    allow(Chef::Application).to receive(:fatal!)
    allow(SecureRandom).to receive(:hex)
      .and_return('ad3313264ea51d8c6a3d1c5b140b9883')
    stub_command('virsh net-list | grep -q default').and_return(true)
    stub_command("/sbin/ppc64_cpu --smt 2>&1 | grep -E 'SMT is off|Machine is" \
      " not SMT capable'").and_return(false)
  end
end

shared_context 'block_storage_stubs' do
  before do
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_servers)
      .and_return('1.1.1.1:5672,2.2.2.2:5672')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', anything)
      .and_return('')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', anything)
      .and_return('cinder')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return('bootstrap-token')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'rbd_secret_uuid')
      .and_return('b0ff3bba-e07b-49b1-beed-09a45552b1ad')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_vmware_secret_name')
      .and_return 'vmware_secret_name'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'guest')
      .and_return('mq-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'netapp')
      .and_return 'netapp-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-block-storage')
      .and_return('cinder-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack_image_cephx_key')
      .and_return('cephx-key')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin')
      .and_return('emc_test_pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'ibmnas_admin')
      .and_return('test_pass')
    allow(Chef::Application).to receive(:fatal!)
  end
end

shared_context 'dashboard_stubs' do
  before do
    allow_any_instance_of(Chef::Recipe).to receive(:memcached_servers)
      .and_return ['hostA:port', 'hostB:port']
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', 'horizon')
      .and_return('test-passes')
    allow_any_instance_of(Chef::Recipe).to receive(:secret)
      .with('certs', 'horizon.pem')
      .and_return('horizon_pem_value')
    allow_any_instance_of(Chef::Recipe).to receive(:secret)
      .with('certs', 'horizon.key')
      .and_return('horizon_key_value')
    stub_command('/usr/sbin/httpd -t')
    stub_command('[ ! -e /etc/httpd/conf/httpd.conf ] && [ -e /etc/redhat-rel' \
      "ease ] && [ $(/sbin/sestatus | grep -c '^Current mode:.*enforcing') -e" \
      'q 1 ]').and_return(true)
    stub_command('[ -e /etc/httpd/conf/httpd.conf ] && [ -e /etc/redhat-relea' \
      "se ] && [ $(/sbin/sestatus | grep -c '^Current mode:.*permissive') -eq" \
      "1 ] && [ $(/sbin/sestatus | grep -c '^Mode from config file:.*enforcin" \
      "g') -eq 1 ]").and_return(true)
  end
end

shared_context 'telemetry_stubs' do
  before do
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_servers)
      .and_return '1.1.1.1:5672,2.2.2.2:5672'
    allow_any_instance_of(Chef::Recipe).to receive(:memcached_servers)
      .and_return([])
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', 'ceilometer')
      .and_return('ceilometer-dbpass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', 'gnocchi')
      .and_return('gnocchi-dbpass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-telemetry')
      .and_return('ceilometer-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-telemetry-metric')
      .and_return('gnocchi-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'guest')
      .and_return('mq-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return('bootstrap-token')
    allow(Chef::Application).to receive(:fatal!)
  end
end
