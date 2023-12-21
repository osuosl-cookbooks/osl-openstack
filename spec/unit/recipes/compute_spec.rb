require_relative '../../spec_helper'

describe 'osl-openstack::compute' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'
      include_context 'compute_stubs'

      it { is_expected.to add_osl_repos_openstack 'compute' }
      it { is_expected.to create_osl_openstack_client 'compute' }
      it { is_expected.to create_osl_openstack_openrc 'compute' }
      it { is_expected.to accept_osl_firewall_openstack 'compute' }
      it { is_expected.to include_recipe 'yum-qemu-ev' }
      it do
        is_expected.to create_osl_ceph_config('default').with(
          client_options: [
            'admin socket = /var/run/ceph/guests/$cluster-$type.$id.$pid.$cctid.asok',
            'rbd concurrent management ops = 20',
            'rbd cache = true',
            'rbd cache writethrough until flush = true',
            'log file = /var/log/ceph/qemu-guest-$pid.log',
          ]
        )
      end
      it { is_expected.to install_kernel_module 'tun' }
      it { is_expected.to load_kernel_module 'tun' }
      it { is_expected.to create_cookbook_file '/etc/sysconfig/network' }
      case pltfrm
      when CENTOS_7
        it do
          is_expected.to install_package %w(
            device-mapper
            device-mapper-multipath
            libguestfs-rescue
            libguestfs-tools
            libvirt
            openstack-nova-compute
            python-libguestfs
            sg3_utils
            sysfsutils
          )
        end
      when ALMA_8
        it do
          is_expected.to install_package %w(
            device-mapper
            device-mapper-multipath
            libguestfs-rescue
            libguestfs-tools
            libvirt
            openstack-nova-compute
            python3-libguestfs
            sg3_utils
            sysfsutils
          )
        end
      end
      it { expect(chef_run.link('/usr/bin/qemu-system-x86_64')).to link_to('/usr/libexec/qemu-kvm') }
      it { is_expected.to create_cookbook_file '/etc/libvirt/libvirtd.conf' }
      it { expect(chef_run.cookbook_file('/etc/libvirt/libvirtd.conf')).to notify('service[libvirtd]').to(:restart) }
      it { is_expected.to enable_service 'libvirtd' }
      it { is_expected.to start_service 'libvirtd' }
      it { is_expected.to run_execute('Deleting default libvirt network').with(command: 'virsh net-destroy default') }
      it { is_expected.to include_recipe 'osl-openstack::compute_common' }
      it { is_expected.to enable_service 'openstack-nova-compute' }
      it { is_expected.to start_service 'openstack-nova-compute' }
      it { expect(chef_run.service('openstack-nova-compute')).to subscribe_to('template[/etc/nova/nova.conf]').on(:restart) }
      it { is_expected.to enable_service 'libvirt-guests' }
      it { is_expected.to start_service 'libvirt-guests' }
      it { is_expected.to install_kernel_module('kvm_intel').with(options: %w(nested=1)) }
      it { is_expected.to include_recipe 'osl-openstack::network' }
      it { is_expected.to include_recipe 'osl-openstack::telemetry_compute' }
      it { is_expected.to install_package 'openstack-cinder' }
      it { is_expected.to create_osl_ceph_keyring('cinder').with(key: 'AQAjbr1aWv+aNBAAoGfqrwX9iSdNmtuvUkwGhA==') }
      it do
        is_expected.to create_osl_ceph_keyring('cinder-backup').with(key: 'AQAxbr1ac4ToKhAAeO6+h90GcsukzHicUNvfLg==')
      end
      it { is_expected.to create_directory('/var/run/ceph/guests').with(owner: 'qemu', group: 'libvirt') }
      it { is_expected.to create_directory('/var/log/ceph').with(owner: 'qemu', group: 'libvirt') }
      it do
        is_expected.to modify_group('ceph-compute').with(
          group_name: 'ceph',
          append: true,
          members: %w(cinder nova qemu)
        )
      end
      it do
        expect(chef_run.group('ceph-compute')).to \
          notify('service[openstack-nova-compute]').to(:restart).immediately
      end
      it do
        expect(chef_run.group('ceph-compute')).to \
          notify('service[libvirtd]').to(:restart).immediately
      end
      it do
        is_expected.to create_template('/var/chef/cache/secret.xml').with(
          source: 'secret.xml.erb',
          user: 'root',
          group: 'root',
          mode: '00600',
          variables: {
            uuid: '8102bb29-f48b-4f6e-81d7-4c59d80ec6b8',
            client_name: 'cinder',
          }
        )
      end
      it { is_expected.to run_execute('virsh secret-define --file /var/chef/cache/secret.xml') }
      it do
        is_expected.to run_execute('update virsh ceph secret').with(
          command: 'virsh secret-set-value --secret 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8 --base64 AQAjbr1aWv+aNBAAoGfqrwX9iSdNmtuvUkwGhA==',
          sensitive: true
        )
      end
      it { is_expected.to delete_file '/var/chef/cache/secret.xml' }
      it do
        is_expected.to create_template('/etc/sysconfig/libvirt-guests').with(
          variables: {
            libvirt_guests: {
              'on_boot' => 'ignore',
              'on_shutdown' => 'shutdown',
              'parallel_shutdown' => '25',
              'shutdown_timeout' => '120',
            },
          }
        )
      end
      it do
        is_expected.to add_osl_authorized_keys('nova_public_key').with(
          user: 'nova',
          key: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYOuLkP1F/Sm/dCJAA7kme+ObO4J8x2HrZU40W8QqW4yFqRPKnW5HYLeUpRzIFzWen/LIn6R6lxTfSAnnD8qEEuKbFjH5WRqJYCJeAyaTBTRyU1FHlcTR/EQ/HVZ38TQwCztZgboFb5zmWqYc3/BYBHGA6XeYN5jRcHvZbyaGL+YA1/KPIjpbQfqIPXdHfodoSNX4qQQccYBq2c/rq3Puh7Q9oVph6a2lq0wWsqYyq0vTGHPKFYShVpwDl2Z3c8eB3P7yFRzOR2VNuezJlOgoHz6D/mBObLj1n+yi07bcGbpwAH/rLEyiy4gVdru2qQAcbDL9Yibk96lovim/IH4dV nova-migration',
          dir_path: '/var/lib/nova/.ssh'
        )
      end
      it do
        is_expected.to add_osl_ssh_key('nova_migration_key').with(
          content: "----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA2Dri5D9Rf0pv3QiQAO5JnvjmzuCfMdh62VONFvEKluMhakTy\np1uR2C3lKUcyBc1np/yyJ+kepcU30gJ5w/KhBLimxYx+VkaiWAiXgMmkwU0clNRR\n5XE0fxEPx1Wd/E0MAs7WYG6BW+c5lqmHN/wWARxgOl3mDeY0XB72W8mhi/mANfyj\nyI6W0H6iD13R36HaEjV+KkEHHGAatnP66tz7oe0PaFaYemtpatMFrKmMqtL0xhzy\nhWEoVacA5dmd3PHgdz+8hUczkdlTbnsyZToKB8+g/5gTmy49Z/sotO23Bm6cAB/6\nyxMosuIFXa7tqkAHGwy/WIm5PepaL4pvyB+HVQIDAQABAoIBAQCgKE2yPewBWoMs\ntpDi/5xsMXPTu7BuXSfxHN+eJH9xb15qthL9PufxtVzNjDxS6+dhF9xlj1fx9Pf5\nh3flWStGsfZk0EErajoI9qQw8iokOxd2bSUTyxvVGjATtyjDndXNpqJG3tLV3Zhc\nLclIAGHUBM6JrM8fcGlL6msTZW9QmupEU69ih0rHGR50in2e+Ofp6TWPbwH2PoRn\nvj3SOyBAOfZMpsTweYwZm/FhkpSY+lxXbsPgEasJNm0/F46U7CHlQVSUY248Y+eB\nDzNI7MC5bknqbWg0TDOQtw41RLaGdVUQy9wqC/UlOWb4mteEZXIx3tfNb5W/5V7G\nYedSjwgpAoGBAPQiCzsWTdC7cR9YbF4d8Tv9uKNCmZG1Q4dxTnhQJcSFsBTr2f2a\nps3Ej3nW0wQZfVOVaU6dUcyQxgm4x2fi+TqhAVGdRLSA8iSJTpC99RUn/JdAW/UA\ngvGI0iCrkq/BYCjjrKI7ZsHv6urE3I0jnh5+H969BsZ6XR6IntwmDshrAoGBAOK9\nnzlOEZO54VGTRuBF1m0E3GBsVDhrsoFpZSVcgv3h84MK2idMP0XvEBxvOI/I2hGI\nkVJ23axxWEmpGzWrBNuJrC0sQKD3g6rdwXSwPsGk0OEXyQVrC3LfLZf3iS+GDSI7\nUYPL01joCXy99fQPCf/dCdpviAlZVO/mlO4Tdd8/AoGAHEQk0L6QW+6X9m0ifvMw\njyWdTynS5g/6tZ/k2gFNnidsb7+vCbHyRjjP8+dvnzXkUN0nyDZm1iydAVsnm1uo\nR6WEpZJz9gJIBvru4ctcqQpsMIb/Hqrkflq9GZND9J2LKLDTuCTwjNveczg/4QeS\nsy0fO4bfVfOs/HANFKhDZekCgYBnEalyZDGLRIDPEzKxui1Zy07eKgAy0YoIV7+Z\nty74d6C5HdLC8F8GzEA3nLtKaRPvynO817m2rKNkgJGU2NPRdAinVClgwoLAxiMt\nhvxQDDrDR4uigeFna1oPbX+X8cjAmdRZI+tDy96cLMHEGp4CCBl1iSN+lHQOxXNH\nseLwAwKBgQDx5QqwZOfmlQ0rx6jf2EoHChbS3JYt1cRJbwzIOakcKh2Jn/agxZJ8\ne9o0x8HI89mJd1WejorvSVN1c3IgV5TG10k5PcmOxlv1OhGNFzWgvMXZmvCwwP40\nX0BwCgHRB7FvPAMu0hrDmEIJ87edGd1ziRYXpA9Lke/4VQk249pwzA==\n-----END RSA PRIVATE KEY-----",
          key_name: 'id_rsa',
          user: 'nova',
          dir_path: '/var/lib/nova/.ssh'
        )
      end
      it do
        is_expected.to create_file('/var/lib/nova/.ssh/config').with(
          content: "Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n",
          user: 'nova',
          group: 'nova',
          mode: '600'
        )
      end
      context 'AMD' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['dmi']['processor']['manufacturer'] = 'AMD'
          end.converge(described_recipe)
        end
        it { is_expected.to install_kernel_module('kvm_amd').with(options: %w(nested=1)) }
      end

      context 'ppc64le' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['kernel']['machine'] = 'ppc64le'
          end.converge(described_recipe)
        end

        case pltfrm
        when CENTOS_7
          it { is_expected.to include_recipe 'yum-kernel-osuosl::install' }
          it { is_expected.to include_recipe 'base::grub' }
        when ALMA_8
          it { is_expected.to_not include_recipe 'yum-kernel-osuosl::install' }
          it { is_expected.to_not include_recipe 'base::grub' }
        end
        it { is_expected.to_not install_kernel_module('kvm_pr') }
        it { is_expected.to_not load_kernel_module('kvm_pr') }
        it { is_expected.to install_kernel_module('kvm_hv') }
        it { is_expected.to load_kernel_module('kvm_hv') }
        it { is_expected.to create_cookbook_file('/etc/rc.d/rc.local').with(mode: '644') }
        it { is_expected.to_not enable_service 'smt_off' }
        it { is_expected.to_not start_service 'smt_off' }

        context 'power8' do
          cached(:chef_run) do
            ChefSpec::SoloRunner.new(pltfrm) do |node|
              node.automatic['kernel']['machine'] = 'ppc64le'
              node.automatic['cpu']['cpu_model'] = 'POWER8E (raw), altivec supported'
            end.converge(described_recipe)
          end
          it { is_expected.to enable_service 'smt_off' }
          it { is_expected.to start_service 'smt_off' }
        end
      end
      context 'aarch64' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['kernel']['machine'] = 'aarch64'
          end.converge(described_recipe)
        end

        case pltfrm
        when CENTOS_7
          it { is_expected.to include_recipe 'yum-kernel-osuosl::install' }
          it { is_expected.to include_recipe 'base::grub' }
        when ALMA_8
          it { is_expected.to_not include_recipe 'yum-kernel-osuosl::install' }
          it { is_expected.to_not include_recipe 'base::grub' }
        end
      end
    end
  end
end
