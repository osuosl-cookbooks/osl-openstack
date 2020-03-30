require 'chefspec'
require 'chefspec/berkshelf'
require_relative 'support/matchers'

REDHAT_OPTS = {
  platform: 'centos',
  version: '7',
  file_cache_path: '/var/chef/cache',
  log_level: :warn,
}.freeze

shared_context 'common_stubs' do
  before do
    node.override['osl-openstack']['endpoint_hostname'] = '10.0.0.10'
    node.override['osl-openstack']['network_hostname'] = '10.0.0.11'
    node.override['osl-openstack']['db_hostname'] = '10.0.0.10'
    node.override['osl-openstack']['database_suffix'] = 'x86'
    node.override['osl-openstack']['databag_suffix'] = 'x86'
    node.override['osl-openstack']['credentials']['ceph']['image_token'] = 'image_token'
    node.override['osl-openstack']['credentials']['ceph']['block_token'] = 'block_token'
    node.override['osl-openstack']['credentials']['ceph']['block_backup_token'] = 'block_backup_token'
    node.override['osl-openstack']['credentials']['ceph']['metrics_token'] = 'metrics_token'
    node.override['ibm_power']['cpu']['cpu_model'] = nil
    node.override['ceph']['fsid-secret'] = '8102bb29-f48b-4f6e-81d7-4c59d80ec6b8'
    node.automatic['filesystem2']['by_mountpoint']
  end
end

shared_context 'ceph_stubs' do
  before do
    stub_command('test -s /etc/yum.repos.d/ceph.repo')
    stub_command('test -s /lib/lsb/init-functions')
    stub_command('getenforce | grep \'Permissive|Disabled\'')
    stub_command('test -f /etc/ceph')
    stub_command('test -s /etc/ceph/ceph.mon.keyring')
    stub_command('test -s /etc/ceph/ceph.client.admin.keyring')
    stub_command('grep \'admin\' /etc/ceph/ceph.mon.keyring')
    stub_command('test -s /var/lib/ceph/mon/ceph-Fauxhai/keyring')
    stub_command('test -f /var/lib/ceph/mon/ceph-Fauxhai/done')
    stub_command('test -d /var/lib/ceph/mgr/ceph-Fauxhai')
    stub_command('test -s /var/lib/ceph/mgr/ceph-Fauxhai/keyring')
    stub_command('test -d /etc/ceph/scripts')
    stub_command('test -f /etc/ceph/scripts/ceph_journal.sh')
    stub_command('test -s /var/lib/ceph/bootstrap-osd/ceph.keyring')
    stub_search('node', 'tags:ceph-mon').and_return(
      [
        {
          fqdn: 'ceph-mon.example.org',
          roles: 'search-ceph-mon',
          ceph: {
            'fsid-secret' => '8102bb29-f48b-4f6e-81d7-4c59d80ec6b8',
          },
          network: {
            interfaces: {
              eth0: {
                addresses: {
                  '10.121.1.1' => {
                    family: 'inet',
                    broadcast: '255.255.255.0',
                  },
                },
              },
            },
          },
        },
      ]
    )
    stub_search('node', 'tags:ceph-rgw').and_return([{}])
    stub_search('node', 'tags:ceph-rbd').and_return([{}])
    stub_search('node', 'tags:ceph-admin').and_return([{}])
    stub_search('node', 'tags:ceph-osd').and_return([{}])
    stub_search('node', 'tags:ceph-mds').and_return([{}])
    stub_search('node', 'tags:ceph-restapi').and_return([{}])
    allow(Chef::EncryptedDataBagItem).to receive(:load)
      .with('ceph', 'openstack')
      .and_raise(Net::HTTPServerException.new(
                   'ceph databag not found',
                   Net::HTTPResponse.new('1.1', '404', '')
                 ))
  end
end

shared_context 'linuxbridge_stubs' do
  before do
    node.override['osl-openstack']['physical_interface_mappings'] =
      [
        name: 'public',
        controller: {
          default: 'eth2',
        },
        compute: {
          default: 'eth1',
        },
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
      .with('user', 'openstack')
      .and_return('openstack')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'user1')
      .and_return('secret1')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return('bootstrap-token')
    allow_any_instance_of(Chef::Recipe).to receive(:secret)
      .with('secrets', 'credential_key0')
      .and_return('thisiscredentialkey0')
    allow_any_instance_of(Chef::Recipe).to receive(:secret)
      .with('secrets', 'credential_key1')
      .and_return('thisiscredentialkey1')
    allow_any_instance_of(Chef::Recipe).to receive(:secret)
      .with('secrets', 'fernet_key0')
      .and_return('thisisfernetkey0')
    allow_any_instance_of(Chef::Recipe).to receive(:secret)
      .with('secrets', 'fernet_key1')
      .and_return('thisisfernetkey1')
    stub_command("[ ! -e /etc/httpd/conf/httpd.conf ] && [ -e /etc/redhat-release ] && [ $(/sbin/sestatus | \
grep -c '^Current mode:.*enforcing') -eq 1 ]").and_return(true)
    stub_command('/usr/sbin/httpd -t')
    allow_any_instance_of(Chef::Recipe).to receive(:search_for)
      .with('os-identity').and_return(
        [{
          'openstack' => {
            'identity' => {
              'admin_tenant_name' => 'admin',
              'admin_user' => 'admin',
            },
          },
        }]
      )
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin')
      .and_return('admin')
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_transport_url)
      .with('identity')
      .and_return('rabbit://openstack:openstack@controller.example.org:5672')
    allow(File).to receive(:symlink?).and_call_original
    allow(File).to receive(:symlink?).with('/etc/httpd/sites-enabled/keystone-admin.conf').and_return(true)
    allow(File).to receive(:symlink?).with('/etc/httpd/sites-enabled/keystone-main.conf').and_return(true)
    stub_search('node', 'role:openstack').and_return(
      [
        {
          ipaddress: '10.0.0.10',
        },
        {
          ipaddress: '10.0.0.11',
        },
      ]
    )
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
      .with('user', 'openstack')
      .and_return('mq-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin')
      .and_return('admin-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_transport_url)
      .with('image')
      .and_return('rabbit://openstack:openstack@controller.example.org:5672')
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
      .with('user', 'openstack')
      .and_return('mq-pass')
    allow(Chef::Application).to receive(:fatal!)
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-compute')
      .and_return('nova-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_transport_url)
      .with('network')
      .and_return('rabbit://openstack:openstack@controller.example.org:5672')
  end
  shared_examples 'custom template banner displayer' do
    it 'shows the custom banner' do
      node.override['openstack']['network']['custom_template_banner'] =
        'custom_template_banner_value'
      expect(chef_run).to render_file(file_name)
        .with_content(/^custom_template_banner_value$/)
    end
  end
  shared_examples 'common network attributes displayer' do |plugin|
    it 'displays the interface_driver common attribute' do
      node.override['openstack']["network_#{plugin}"]['conf']['DEFAULT'] \
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
        node.override['openstack']['network_dhcp']['conf']['DEFAULT'][attr] =
          "network_dhcp_#{attr}_value"
        expect(chef_run).to render_file(file_name)
          .with_content(/^#{attr} = network_dhcp_#{attr}_value$/)
      end
    end
  end
end

shared_context 'compute_stubs' do
  before do
    node.override['osl-openstack']['nova_public_key'] = 'ssh public key'
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
              'admin_user' => 'admin',
            },
          },
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
      .with('db', 'nova_cell0')
      .and_return('nova_cell0_db_pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'openstack')
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
      .with('service', 'openstack-placement')
      .and_return('placement-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'rbd_block_storage')
      .and_return 'cinder-rbd-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:memcached_servers)
      .and_return []
    allow(Chef::Application).to receive(:fatal!)
    allow(SecureRandom).to receive(:hex)
      .and_return('ad3313264ea51d8c6a3d1c5b140b9883')
    stub_command('virsh net-list | grep -q default').and_return(true)
    stub_command('virsh secret-set-value --secret 00000000-0000-0000-0000-000000000000 --base64 $(ceph-authtool \
-p -n client.cinder /etc/ceph/ceph.client.cinder.keyring)').and_return(false)
    stub_command('virsh secret-get-value 00000000-0000-0000-0000-000000000000 | grep $(ceph-authtool -p -n \
client.cinder /etc/ceph/ceph.client.cinder.keyring)').and_return(false)
    stub_command('nova-manage api_db sync').and_return(true)
    stub_command('nova-manage cell_v2 map_cell0 --database_connection mysql+pymysql://nova_cell0:mypass@127.0.0.1/\
nova_cell0?charset=utf8').and_return(true)
    stub_command('nova-manage cell_v2 create_cell --verbose --name cell1').and_return(true)
    stub_command('nova-manage cell_v2 list_cells | grep -q cell0').and_return(false)
    stub_command('nova-manage cell_v2 list_cells | grep -q cell1').and_return(false)
    stub_command('nova-manage cell_v2 discover_hosts').and_return(true)
    stub_command("/sbin/ppc64_cpu --smt 2>&1 | grep -E 'SMT is off|Machine is" \
      " not SMT capable'").and_return(false)
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_transport_url)
      .with('compute')
      .and_return('rabbit://openstack:openstack@controller.example.org:5672')
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
      .with('user', 'openstack')
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
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_transport_url)
      .with('block_storage')
      .and_return('rabbit://openstack:openstack@controller.example.org:5672')
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
      .with('service', 'openstack-aodh')
      .and_return('aodh-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-telemetry')
      .and_return('ceilometer-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-telemetry_metric')
      .and_return('gnocchi-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'openstack')
      .and_return('mq-pass')
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return('bootstrap-token')
    allow(Chef::Application).to receive(:fatal!)
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_transport_url)
      .with('telemetry')
      .and_return('rabbit://openstack:openstack@controller.example.org:5672')
    stub_command('grep -q curated_sname /usr/lib/python2.7/site-packages/ceilometer/publisher/prometheus.py')
      .and_return(false)
    stub_command('grep -q s.project_id /usr/lib/python2.7/site-packages/ceilometer/publisher/prometheus.py')
      .and_return(false)
  end
end

shared_context 'orchestration_stubs' do
  before do
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_servers)
      .and_return '1.1.1.1:5672,2.2.2.2:5672'
    allow_any_instance_of(Chef::Recipe).to receive(:address_for)
      .with('lo')
      .and_return '127.0.1.1'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return 'bootstrap-token'

    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', 'heat')
      .and_return 'heat'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'guest')
      .and_return 'mq-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin-user')
      .and_return 'admin-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-orchestration')
      .and_return 'heat-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin')
      .and_return 'admin-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'orchestration_auth_encryption_key')
      .and_return 'auth_encryption_key_secret'
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_transport_url)
      .with('orchestration')
      .and_return('rabbit://openstack:openstack@controller.example.org:5672')
    allow(Chef::Application).to receive(:fatal!)
  end
end
