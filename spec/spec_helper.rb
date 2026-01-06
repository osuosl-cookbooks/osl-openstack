require 'chefspec'
require 'chefspec/berkshelf'

ALMA_9 = {
  platform: 'almalinux',
  version: '9',
  file_cache_path: '/var/chef/cache',
  log_level: :warn,
}.freeze

ALMA_8 = {
  platform: 'almalinux',
  version: '8',
  file_cache_path: '/var/chef/cache',
  log_level: :warn,
}.freeze

ALL_PLATFORMS = [
  ALMA_9,
  ALMA_8,
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
        "endpoint": 'controller.testing.osuosl.org',
        "region": 'RegionOne',
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
          AvailabilityZoneFilter
          ComputeFilter
          ComputeCapabilitiesFilter
          ImagePropertiesFilter
          ServerGroupAntiAffinityFilter
          ServerGroupAffinityFilter
        ),
        "endpoint": 'controller.testing.osuosl.org',
        "region": 'RegionOne',
        'libvirt_guests' => {
          "on_boot": 'ignore',
          "on_shutdown": 'shutdown',
          "parallel_shutdown": '25',
          "shutdown_timeout": '120',
        },
        'ksm' => {
          'npages_max' => 2500,
          'thres_coef' => 25,
          'monitor_interval' => 30,
        },
        'local_storage' => {
          'node1.testing.osuosl.org' => true,
        },
        "nova_migration_key": "----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA2Dri5D9Rf0pv3QiQAO5JnvjmzuCfMdh62VONFvEKluMhakTy\np1uR2C3lKUcyBc1np/yyJ+kepcU30gJ5w/KhBLimxYx+VkaiWAiXgMmkwU0clNRR\n5XE0fxEPx1Wd/E0MAs7WYG6BW+c5lqmHN/wWARxgOl3mDeY0XB72W8mhi/mANfyj\nyI6W0H6iD13R36HaEjV+KkEHHGAatnP66tz7oe0PaFaYemtpatMFrKmMqtL0xhzy\nhWEoVacA5dmd3PHgdz+8hUczkdlTbnsyZToKB8+g/5gTmy49Z/sotO23Bm6cAB/6\nyxMosuIFXa7tqkAHGwy/WIm5PepaL4pvyB+HVQIDAQABAoIBAQCgKE2yPewBWoMs\ntpDi/5xsMXPTu7BuXSfxHN+eJH9xb15qthL9PufxtVzNjDxS6+dhF9xlj1fx9Pf5\nh3flWStGsfZk0EErajoI9qQw8iokOxd2bSUTyxvVGjATtyjDndXNpqJG3tLV3Zhc\nLclIAGHUBM6JrM8fcGlL6msTZW9QmupEU69ih0rHGR50in2e+Ofp6TWPbwH2PoRn\nvj3SOyBAOfZMpsTweYwZm/FhkpSY+lxXbsPgEasJNm0/F46U7CHlQVSUY248Y+eB\nDzNI7MC5bknqbWg0TDOQtw41RLaGdVUQy9wqC/UlOWb4mteEZXIx3tfNb5W/5V7G\nYedSjwgpAoGBAPQiCzsWTdC7cR9YbF4d8Tv9uKNCmZG1Q4dxTnhQJcSFsBTr2f2a\nps3Ej3nW0wQZfVOVaU6dUcyQxgm4x2fi+TqhAVGdRLSA8iSJTpC99RUn/JdAW/UA\ngvGI0iCrkq/BYCjjrKI7ZsHv6urE3I0jnh5+H969BsZ6XR6IntwmDshrAoGBAOK9\nnzlOEZO54VGTRuBF1m0E3GBsVDhrsoFpZSVcgv3h84MK2idMP0XvEBxvOI/I2hGI\nkVJ23axxWEmpGzWrBNuJrC0sQKD3g6rdwXSwPsGk0OEXyQVrC3LfLZf3iS+GDSI7\nUYPL01joCXy99fQPCf/dCdpviAlZVO/mlO4Tdd8/AoGAHEQk0L6QW+6X9m0ifvMw\njyWdTynS5g/6tZ/k2gFNnidsb7+vCbHyRjjP8+dvnzXkUN0nyDZm1iydAVsnm1uo\nR6WEpZJz9gJIBvru4ctcqQpsMIb/Hqrkflq9GZND9J2LKLDTuCTwjNveczg/4QeS\nsy0fO4bfVfOs/HANFKhDZekCgYBnEalyZDGLRIDPEzKxui1Zy07eKgAy0YoIV7+Z\nty74d6C5HdLC8F8GzEA3nLtKaRPvynO817m2rKNkgJGU2NPRdAinVClgwoLAxiMt\nhvxQDDrDR4uigeFna1oPbX+X8cjAmdRZI+tDy96cLMHEGp4CCBl1iSN+lHQOxXNH\nseLwAwKBgQDx5QqwZOfmlQ0rx6jf2EoHChbS3JYt1cRJbwzIOakcKh2Jn/agxZJ8\ne9o0x8HI89mJd1WejorvSVN1c3IgV5TG10k5PcmOxlv1OhGNFzWgvMXZmvCwwP40\nX0BwCgHRB7FvPAMu0hrDmEIJ87edGd1ziRYXpA9Lke/4VQk249pwzA==\n-----END RSA PRIVATE KEY-----",
        "nova_public_key": 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYOuLkP1F/Sm/dCJAA7kme+ObO4J8x2HrZU40W8QqW4yFqRPKnW5HYLeUpRzIFzWen/LIn6R6lxTfSAnnD8qEEuKbFjH5WRqJYCJeAyaTBTRyU1FHlcTR/EQ/HVZ38TQwCztZgboFb5zmWqYc3/BYBHGA6XeYN5jRcHvZbyaGL+YA1/KPIjpbQfqIPXdHfodoSNX4qQQccYBq2c/rq3Puh7Q9oVph6a2lq0wWsqYyq0vTGHPKFYShVpwDl2Z3c8eB3P7yFRzOR2VNuezJlOgoHz6D/mBObLj1n+yi07bcGbpwAH/rLEyiy4gVdru2qQAcbDL9Yibk96lovim/IH4dV nova-migration',
        'pci_alias' => {
          'controller2.testing.osuosl.org' => '{ "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }',
          'node1.testing.osuosl.org' => '{ "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }',
        },
        'pci_passthrough_whitelist' => {
          'node1.testing.osuosl.org' => '{ "vendor_id": "10de", "product_id": "1db5" }',
        },
        'service' => {
          "user": 'nova',
          "pass": 'nova',
        },
      },
      'dashboard' => {
        "aliases": [
          'controller1.testing.osuosl.org',
        ],
        "endpoint": 'controller.testing.osuosl.org',
        'db' => {
          "user": 'horizon',
          "pass": 'horizon',
        },
        'regions' => {
          "RegionOne": 'https://controller.testing.osuosl.org:5000/v3',
          "RegionTwo": 'https://controller.testing.osuosl.org:5000/v3',
        },
        "secret_key": '-#45g2*o=8mhe(10if%*65@g#z0r#r7m__w6kwq8s9@n%12a11',
      },
      'database_server' => {
        "suffix": 'x86',
        "endpoint": 'localhost',
      },
      'identity' => {
        "aliases": [
          'controller1.testing.osuosl.org',
        ],
        "endpoint": 'controller.testing.osuosl.org',
        'db' => {
          "user": 'keystone',
          "pass": 'keystone',
        },
      },
      'image' => {
        "endpoint": 'controller.testing.osuosl.org',
        "region": 'RegionOne',
        'db' => {
          "user": 'glance',
          "pass": 'glance',
        },
        'ceph' => {
          "image_token": 'AQANbr1aPR2EIhAASn5EW+qjhoXJAtIqGYE5jQ==',
          "rbd_store_pool": 'images',
          "rbd_store_user": 'glance',
        },
        'local_storage' => {
          'node1.testing.osuosl.org' => true,
        },
        'service' => {
          "user": 'glance',
          "pass": 'glance',
        },
      },
      'messaging' => {
        "endpoint": 'controller.testing.osuosl.org',
        "user": 'openstack',
        "pass": 'openstack',
      },
      'memcached' => {
        "endpoint": 'controller.testing.osuosl.org:11211',
      },
      'network' => {
        "endpoint": 'controller.testing.osuosl.org',
        "region": 'RegionOne',
        'db' => {
          "user": 'neutron',
          "pass": 'neutron',
        },
        "nova_metadata_host": 'controller.testing.osuosl.org',
        "metadata_proxy_shared_secret": '2SJh0RuO67KpZ63z',
        'physical_interface_mappings' => [
          {
            "name": 'public',
            'subnet': '10.0.0.0/24',
            'uuid': '8df74e06-c4aa-4eb2-b312-0e915bf8f97f',
            'controller' => {
              "default": 'eth1',
              "controller2.testing.osuosl.org": 'p1p2',
            },
            'compute' => {
              "default": 'eth1',
              "node1.testing.osuosl.org": 'eno1',
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
            "controller2.testing.osuosl.org": 'p2p1',
          },
          'compute' => {
            "default": 'lo',
            "node1.testing.osuosl.org": 'eno2',
          },
        },
      },
      'openrc' => {
        "region": 'RegionOne',
      },
      'orchestration' => {
        "auth_encryption_key": '4CFk1URr4Ln37kKRNSypwjI7vv7jfLQE',
        "region": 'RegionOne',
        'db' => {
          "user": 'heat',
          "pass": 'heat',
        },
        "endpoint": 'controller.testing.osuosl.org',
        "heat_domain_admin": 'heat_domain_admin',
        'service' => {
          "user": 'heat',
          "pass": 'heat',
        },
      },
      'placement' => {
        "endpoint": 'controller.testing.osuosl.org',
        "region": 'RegionOne',
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
    allow(File).to receive(:readlines).and_call_original
    allow(File).to receive(:readlines).with('/etc/yum/pluginconf.d/versionlock.list').and_return([])
  end
end

shared_context 'region2_stubs' do
  before do
    stub_data_bag_item('openstack', 'x86').and_return(
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
        "disk_allocation_ratio": '1.5',
        'db' => {
          "user": 'nova',
          "pass": 'nova',
        },
        'enabled_filters' => %w(
          AggregateInstanceExtraSpecsFilter
          PciPassthroughFilter
          AvailabilityZoneFilter
          ComputeFilter
          ComputeCapabilitiesFilter
          ImagePropertiesFilter
          ServerGroupAntiAffinityFilter
          ServerGroupAffinityFilter
        ),
        "endpoint": 'controller_region2.testing.osuosl.org',
        "region": 'RegionTwo',
        'libvirt_guests' => {
          "on_boot": 'ignore',
          "on_shutdown": 'shutdown',
          "parallel_shutdown": '25',
          "shutdown_timeout": '120',
        },
        'ksm' => {
          'npages_max' => 2500,
          'thres_coef' => 25,
          'monitor_interval' => 30,
        },
        'cinder_disabled' => {
          'node1.testing.osuosl.org' => true,
        },
        'local_storage' => {
          'node1.testing.osuosl.org' => true,
        },
        "nova_migration_key": "----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA2Dri5D9Rf0pv3QiQAO5JnvjmzuCfMdh62VONFvEKluMhakTy\np1uR2C3lKUcyBc1np/yyJ+kepcU30gJ5w/KhBLimxYx+VkaiWAiXgMmkwU0clNRR\n5XE0fxEPx1Wd/E0MAs7WYG6BW+c5lqmHN/wWARxgOl3mDeY0XB72W8mhi/mANfyj\nyI6W0H6iD13R36HaEjV+KkEHHGAatnP66tz7oe0PaFaYemtpatMFrKmMqtL0xhzy\nhWEoVacA5dmd3PHgdz+8hUczkdlTbnsyZToKB8+g/5gTmy49Z/sotO23Bm6cAB/6\nyxMosuIFXa7tqkAHGwy/WIm5PepaL4pvyB+HVQIDAQABAoIBAQCgKE2yPewBWoMs\ntpDi/5xsMXPTu7BuXSfxHN+eJH9xb15qthL9PufxtVzNjDxS6+dhF9xlj1fx9Pf5\nh3flWStGsfZk0EErajoI9qQw8iokOxd2bSUTyxvVGjATtyjDndXNpqJG3tLV3Zhc\nLclIAGHUBM6JrM8fcGlL6msTZW9QmupEU69ih0rHGR50in2e+Ofp6TWPbwH2PoRn\nvj3SOyBAOfZMpsTweYwZm/FhkpSY+lxXbsPgEasJNm0/F46U7CHlQVSUY248Y+eB\nDzNI7MC5bknqbWg0TDOQtw41RLaGdVUQy9wqC/UlOWb4mteEZXIx3tfNb5W/5V7G\nYedSjwgpAoGBAPQiCzsWTdC7cR9YbF4d8Tv9uKNCmZG1Q4dxTnhQJcSFsBTr2f2a\nps3Ej3nW0wQZfVOVaU6dUcyQxgm4x2fi+TqhAVGdRLSA8iSJTpC99RUn/JdAW/UA\ngvGI0iCrkq/BYCjjrKI7ZsHv6urE3I0jnh5+H969BsZ6XR6IntwmDshrAoGBAOK9\nnzlOEZO54VGTRuBF1m0E3GBsVDhrsoFpZSVcgv3h84MK2idMP0XvEBxvOI/I2hGI\nkVJ23axxWEmpGzWrBNuJrC0sQKD3g6rdwXSwPsGk0OEXyQVrC3LfLZf3iS+GDSI7\nUYPL01joCXy99fQPCf/dCdpviAlZVO/mlO4Tdd8/AoGAHEQk0L6QW+6X9m0ifvMw\njyWdTynS5g/6tZ/k2gFNnidsb7+vCbHyRjjP8+dvnzXkUN0nyDZm1iydAVsnm1uo\nR6WEpZJz9gJIBvru4ctcqQpsMIb/Hqrkflq9GZND9J2LKLDTuCTwjNveczg/4QeS\nsy0fO4bfVfOs/HANFKhDZekCgYBnEalyZDGLRIDPEzKxui1Zy07eKgAy0YoIV7+Z\nty74d6C5HdLC8F8GzEA3nLtKaRPvynO817m2rKNkgJGU2NPRdAinVClgwoLAxiMt\nhvxQDDrDR4uigeFna1oPbX+X8cjAmdRZI+tDy96cLMHEGp4CCBl1iSN+lHQOxXNH\nseLwAwKBgQDx5QqwZOfmlQ0rx6jf2EoHChbS3JYt1cRJbwzIOakcKh2Jn/agxZJ8\ne9o0x8HI89mJd1WejorvSVN1c3IgV5TG10k5PcmOxlv1OhGNFzWgvMXZmvCwwP40\nX0BwCgHRB7FvPAMu0hrDmEIJ87edGd1ziRYXpA9Lke/4VQk249pwzA==\n-----END RSA PRIVATE KEY-----",
        "nova_public_key": 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYOuLkP1F/Sm/dCJAA7kme+ObO4J8x2HrZU40W8QqW4yFqRPKnW5HYLeUpRzIFzWen/LIn6R6lxTfSAnnD8qEEuKbFjH5WRqJYCJeAyaTBTRyU1FHlcTR/EQ/HVZ38TQwCztZgboFb5zmWqYc3/BYBHGA6XeYN5jRcHvZbyaGL+YA1/KPIjpbQfqIPXdHfodoSNX4qQQccYBq2c/rq3Puh7Q9oVph6a2lq0wWsqYyq0vTGHPKFYShVpwDl2Z3c8eB3P7yFRzOR2VNuezJlOgoHz6D/mBObLj1n+yi07bcGbpwAH/rLEyiy4gVdru2qQAcbDL9Yibk96lovim/IH4dV nova-migration',
        'pci_alias' => {
          'controller2.testing.osuosl.org' => '{ "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }',
          'node1.testing.osuosl.org' => '{ "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }',
        },
        'pci_passthrough_whitelist' => {
          'node1.testing.osuosl.org' => '{ "vendor_id": "10de", "product_id": "1db5" }',
        },
        'service' => {
          "user": 'nova',
          "pass": 'nova',
        },
      },
      'database_server' => {
        "suffix": 'x86',
        "endpoint": 'localhost_region2',
      },
      'identity' => {
        "endpoint": 'controller.testing.osuosl.org',
      },
      'image' => {
        "endpoint": 'controller_region2.testing.osuosl.org',
        "region": 'RegionTwo',
        'db' => {
          "user": 'glance',
          "pass": 'glance',
        },
        'local_storage' => {
          'node1.testing.osuosl.org' => true,
        },
        'service' => {
          "user": 'glance',
          "pass": 'glance',
        },
      },
      'messaging' => {
        "endpoint": 'controller_region2.testing.osuosl.org',
        "user": 'openstack',
        "pass": 'openstack',
      },
      'memcached' => {
        "endpoint": 'controller_region2.testing.osuosl.org:11211',
      },
      'network' => {
        "endpoint": 'controller_region2.testing.osuosl.org',
        "region": 'RegionTwo',
        'db' => {
          "user": 'neutron',
          "pass": 'neutron',
        },
        "nova_metadata_host": 'controller_region2.testing.osuosl.org',
        "metadata_proxy_shared_secret": '2SJh0RuO67KpZ63z',
        'physical_interface_mappings' => [
          {
            "name": 'public',
            'subnet': '10.0.0.0/24',
            'uuid': '8df74e06-c4aa-4eb2-b312-0e915bf8f97f',
            'controller' => {
              "default": 'eth1',
              "controller2.testing.osuosl.org": 'p1p2',
            },
            'compute' => {
              "default": 'eth1',
              "node1.testing.osuosl.org": 'eno1',
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
            "controller2.testing.osuosl.org": 'p2p1',
          },
          'compute' => {
            "default": 'lo',
            "node1.testing.osuosl.org": 'eno2',
          },
        },
      },
      'openrc' => {
        "region": 'RegionTwo',
      },
      'placement' => {
        "endpoint": 'controller_region2.testing.osuosl.org',
        "region": 'RegionTwo',
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
    allow(File).to receive(:read).with('/etc/ceph/ceph.conf').and_return(nil)
    allow(File).to receive(:readlines).and_call_original
    allow(File).to receive(:readlines).with('/etc/yum/pluginconf.d/versionlock.list').and_return([])
  end
end

shared_context 'dashboard_noregion_stubs' do
  before do
    stub_data_bag_item('openstack', 'x86').and_return(
      'identity' => {
        "endpoint": 'controller.testing.osuosl.org',
      },
      'dashboard' => {
        "aliases": [
          'controller1.testing.osuosl.org',
        ],
        "endpoint": 'controller.testing.osuosl.org',
        'db' => {
          "user": 'horizon',
          "pass": 'horizon',
        },
        "secret_key": '-#45g2*o=8mhe(10if%*65@g#z0r#r7m__w6kwq8s9@n%12a11',
      },
      'memcached' => {
        "endpoint": 'controller.testing.osuosl.org:11211',
      }
    )
    stubs_for_resource('execute[rabbitmq: add user openstack]') do |resource|
      allow(resource).to receive_shell_out('rabbitmqctl -q list_users')
    end
    stubs_for_resource('execute[rabbitmq: set permissions openstack]') do |resource|
      allow(resource).to receive_shell_out('rabbitmqctl -q list_permissions')
    end
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/etc/ceph/ceph.conf').and_return(nil)
    allow(File).to receive(:readlines).and_call_original
    allow(File).to receive(:readlines).with('/etc/yum/pluginconf.d/versionlock.list').and_return([])
  end
end

shared_context 'network_stubs' do
  before do
    stub_command('ip netns exec qdhcp-8df74e06-c4aa-4eb2-b312-0e915bf8f97f iptables -S | egrep "10.0.0.0/24.*port 53.*DROP"')
  end
end

shared_context 'compute_stubs' do
  before do
    stub_command('virsh net-list | grep -q default').and_return(true)
    stub_command('virsh secret-list | grep 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8')
    stub_command('virsh secret-get-value 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8 | grep AQAjbr1aWv+aNBAAoGfqrwX9iSdNmtuvUkwGhA==')
  end
end
