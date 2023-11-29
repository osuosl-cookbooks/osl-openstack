require 'chefspec'
require 'chefspec/berkshelf'

CENTOS_7 = {
  platform: 'centos',
  version: '7',
  file_cache_path: '/var/chef/cache',
  log_level: :warn,
}.freeze

ALL_PLATFORMS = [
  CENTOS_7,
].freeze

shared_context 'common_stubs' do
  before do
    stub_data_bag_item('openstack', 'x86').and_return(
      'block-storage' => {
        'ceph' => {
          "backup_ceph_pool": 'backups',
          "block_backup_rbd_store_user": 'cinder-backup',
          "block_backup_token": 'AQAxbr1ac4ToKhAAeO6+h90GcsukzHicUNvfLg==',
          "block_rbd_pool": 'volumes',
          "block_ssd_rbd_pool": 'volumes_ssd',
          "block_token": 'AQAjbr1aWv+aNBAAoGfqrwX9iSdNmtuvUkwGhA==',
          "rbd_store_user": 'cinder',
        },
        'db' => {
          "user": 'cinder',
          "pass": 'cinder',
        },
        "endpoint": 'controller.example.com',
        'service' => {
          "user": 'cinder',
          "pass": 'cinder',
        },
      },
      'compute_api' => {
        'db' => {
          "user": 'nova',
          "pass": 'nova',
        },
      },
      'compute_cell0' => {
        'db' => {
          "user": 'nova',
          "pass": 'nova',
        },
      },
      'compute' => {
        'ceph' => {
          "block_token": 'AQAjbr1aWv+aNBAAoGfqrwX9iSdNmtuvUkwGhA==',
          "images_rbd_pool": 'vms',
          "rbd_user": 'cinder',
        },
        "disk_allocation_ratio": '1.5',
        'db' => {
          "user": 'nova',
          "pass": 'nova',
        },
        'enabled_filters' => %w(
          AggregateInstanceExtraSpecsFilter
          PciPassthroughFilter
          RetryFilter
          AvailabilityZoneFilter
          RamFilter
          ComputeFilter
          ComputeCapabilitiesFilter
          ImagePropertiesFilter
          ServerGroupAntiAffinityFilter
          ServerGroupAffinityFilter
        ),
        "endpoint": 'controller.example.com',
        'libvirt_guests' => {
          "on_boot": 'ignore',
          "on_shutdown": 'shutdown',
          "parallel_shutdown": '25',
          "shutdown_timeout": '120',
        },
        "nova_migration_key": "----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA2Dri5D9Rf0pv3QiQAO5JnvjmzuCfMdh62VONFvEKluMhakTy\np1uR2C3lKUcyBc1np/yyJ+kepcU30gJ5w/KhBLimxYx+VkaiWAiXgMmkwU0clNRR\n5XE0fxEPx1Wd/E0MAs7WYG6BW+c5lqmHN/wWARxgOl3mDeY0XB72W8mhi/mANfyj\nyI6W0H6iD13R36HaEjV+KkEHHGAatnP66tz7oe0PaFaYemtpatMFrKmMqtL0xhzy\nhWEoVacA5dmd3PHgdz+8hUczkdlTbnsyZToKB8+g/5gTmy49Z/sotO23Bm6cAB/6\nyxMosuIFXa7tqkAHGwy/WIm5PepaL4pvyB+HVQIDAQABAoIBAQCgKE2yPewBWoMs\ntpDi/5xsMXPTu7BuXSfxHN+eJH9xb15qthL9PufxtVzNjDxS6+dhF9xlj1fx9Pf5\nh3flWStGsfZk0EErajoI9qQw8iokOxd2bSUTyxvVGjATtyjDndXNpqJG3tLV3Zhc\nLclIAGHUBM6JrM8fcGlL6msTZW9QmupEU69ih0rHGR50in2e+Ofp6TWPbwH2PoRn\nvj3SOyBAOfZMpsTweYwZm/FhkpSY+lxXbsPgEasJNm0/F46U7CHlQVSUY248Y+eB\nDzNI7MC5bknqbWg0TDOQtw41RLaGdVUQy9wqC/UlOWb4mteEZXIx3tfNb5W/5V7G\nYedSjwgpAoGBAPQiCzsWTdC7cR9YbF4d8Tv9uKNCmZG1Q4dxTnhQJcSFsBTr2f2a\nps3Ej3nW0wQZfVOVaU6dUcyQxgm4x2fi+TqhAVGdRLSA8iSJTpC99RUn/JdAW/UA\ngvGI0iCrkq/BYCjjrKI7ZsHv6urE3I0jnh5+H969BsZ6XR6IntwmDshrAoGBAOK9\nnzlOEZO54VGTRuBF1m0E3GBsVDhrsoFpZSVcgv3h84MK2idMP0XvEBxvOI/I2hGI\nkVJ23axxWEmpGzWrBNuJrC0sQKD3g6rdwXSwPsGk0OEXyQVrC3LfLZf3iS+GDSI7\nUYPL01joCXy99fQPCf/dCdpviAlZVO/mlO4Tdd8/AoGAHEQk0L6QW+6X9m0ifvMw\njyWdTynS5g/6tZ/k2gFNnidsb7+vCbHyRjjP8+dvnzXkUN0nyDZm1iydAVsnm1uo\nR6WEpZJz9gJIBvru4ctcqQpsMIb/Hqrkflq9GZND9J2LKLDTuCTwjNveczg/4QeS\nsy0fO4bfVfOs/HANFKhDZekCgYBnEalyZDGLRIDPEzKxui1Zy07eKgAy0YoIV7+Z\nty74d6C5HdLC8F8GzEA3nLtKaRPvynO817m2rKNkgJGU2NPRdAinVClgwoLAxiMt\nhvxQDDrDR4uigeFna1oPbX+X8cjAmdRZI+tDy96cLMHEGp4CCBl1iSN+lHQOxXNH\nseLwAwKBgQDx5QqwZOfmlQ0rx6jf2EoHChbS3JYt1cRJbwzIOakcKh2Jn/agxZJ8\ne9o0x8HI89mJd1WejorvSVN1c3IgV5TG10k5PcmOxlv1OhGNFzWgvMXZmvCwwP40\nX0BwCgHRB7FvPAMu0hrDmEIJ87edGd1ziRYXpA9Lke/4VQk249pwzA==\n-----END RSA PRIVATE KEY-----",
        "nova_public_key": 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYOuLkP1F/Sm/dCJAA7kme+ObO4J8x2HrZU40W8QqW4yFqRPKnW5HYLeUpRzIFzWen/LIn6R6lxTfSAnnD8qEEuKbFjH5WRqJYCJeAyaTBTRyU1FHlcTR/EQ/HVZ38TQwCztZgboFb5zmWqYc3/BYBHGA6XeYN5jRcHvZbyaGL+YA1/KPIjpbQfqIPXdHfodoSNX4qQQccYBq2c/rq3Puh7Q9oVph6a2lq0wWsqYyq0vTGHPKFYShVpwDl2Z3c8eB3P7yFRzOR2VNuezJlOgoHz6D/mBObLj1n+yi07bcGbpwAH/rLEyiy4gVdru2qQAcbDL9Yibk96lovim/IH4dV nova-migration',
        'service' => {
          "user": 'nova',
          "pass": 'nova',
        },
      },
      'dashboard' => {
        "endpoint": 'controller.example.com',
        'db' => {
          "user": 'horizon',
          "pass": 'horizon',
        },
        "secret_key": '-#45g2*o=8mhe(10if%*65@g#z0r#r7m__w6kwq8s9@n%12a11',
      },
      'database_server' => {
        "suffix": 'x86',
        "endpoint": 'localhost',
      },
      'identity' => {
        "endpoint": 'controller.example.com',
        'db' => {
          "user": 'keystone',
          "pass": 'keystone',
        },
      },
      'image' => {
        "endpoint": 'controller.example.com',
        'db' => {
          "user": 'glance',
          "pass": 'glance',
        },
        'ceph' => {
          "image_token": 'AQANbr1aPR2EIhAASn5EW+qjhoXJAtIqGYE5jQ==',
          "rbd_store_pool": 'images',
          "rbd_store_user": 'glance',
        },
        'service' => {
          "user": 'glance',
          "pass": 'glance',
        },
      },
      'messaging' => {
        "endpoint": 'controller.example.com',
        "user": 'openstack',
        "pass": 'openstack',
      },
      'memcached' => {
        "endpoint": 'controller.example.com:11211',
      },
      'network' => {
        "endpoint": 'controller.example.com',
        'db' => {
          "user": 'neutron',
          "pass": 'neutron',
        },
        "nova_metadata_host": 'controller.example.com',
        "metadata_proxy_shared_secret": '2SJh0RuO67KpZ63z',
        'physical_interface_mappings' => [
          {
            "name": 'public',
            'controller' => {
              "default": 'eth1',
            },
            'compute' => {
              "default": 'eth1',
            },
          },
          {
            "name": 'private1',
            'controller' => {
              "default": 'disabled',
            },
            'compute' => {
              "default": 'disabled',
            },
          },
        ],
        'service' => {
          "user": 'neutron',
          "pass": 'neutron',
        },
        'vxlan_interface' => {
          'controller' => {
            "default": 'lo',
          },
          'compute' => {
            "default": 'lo',
          },
        },
      },
      'orchestration' => {
        "auth_encryption_key": '4CFk1URr4Ln37kKRNSypwjI7vv7jfLQE',
        'db' => {
          "user": 'heat',
          "pass": 'heat',
        },
        "endpoint": 'controller.example.com',
        "heat_domain_admin": 'heat_domain_admin',
        'service' => {
          "user": 'heat',
          "pass": 'heat',
        },
      },
      'placement' => {
        "endpoint": 'controller.example.com',
        'db' => {
          "user": 'placement',
          "pass": 'placement',
        },
        'service' => {
          "user": 'placement',
          "pass": 'placement',
        },
      },
      'telemetry' => {
        'db' => {
          "user": 'ceilometer',
          "pass": 'ceilometer',
        },
        'pipeline' => {
          'publishers' => [
            'prometheus://localhost:9091/metrics/job/ceilometer',
          ],
        },
        'service' => {
          "user": 'ceilometer',
          "pass": 'ceilometer',
        },
      },
      'users' => {
        "admin": 'admin',
      }
    )
    stubs_for_resource('execute[rabbitmq: add user openstack]') do |resource|
      allow(resource).to receive_shell_out('rabbitmqctl -q list_users')
    end
    stubs_for_resource('execute[rabbitmq: set permissions openstack]') do |resource|
      allow(resource).to receive_shell_out('rabbitmqctl -q list_permissions')
    end
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/etc/ceph/ceph.conf').and_return('fsid = 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8')
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
