require_relative '../../spec_helper'

describe 'osl-openstack::compute' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'
      include_context 'compute_stubs'

      it { is_expected.to create_osl_openstack_client('compute').with(firewall: true, openrc: true) }
      it { is_expected.to accept_osl_firewall_hpnssh 'osl-openstack' }
      it { is_expected.to install_osl_hpnssh 'osl-openstack' }
      it { is_expected.to include_recipe 'osl-ceph' }
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
      it do
        is_expected.to install_kernel_module('nf_conntrack').with(options: %w(hashsize=524288))
      end
      it { is_expected.to load_kernel_module 'nf_conntrack' }
      # sysctl and osl_sysfs_param both coerce value to a String
      it do
        is_expected.to apply_sysctl('net.netfilter.nf_conntrack_max').with(value: '2097152')
      end
      it do
        is_expected.to apply_sysctl('net.netfilter.nf_conntrack_tcp_timeout_established')
          .with(value: '86400')
      end
      it do
        is_expected.to set_osl_sysfs_param('/sys/module/nf_conntrack/parameters/hashsize')
          .with(value: '524288')
      end
      it do
        is_expected.to install_package %w(
          device-mapper
          device-mapper-multipath
          guestfs-tools
          libguestfs-rescue
          libvirt
          python3-libguestfs
          qemu-kvm
          qemu-kvm-device-display-virtio-gpu
          qemu-kvm-device-display-virtio-gpu-pci
          qemu-kvm-device-display-virtio-vga
          sg3_utils
          sysfsutils
          virt-win-reg
        )
      end
      it { is_expected.to upgrade_package 'osuosl-openstack-nova-compute' }
      it { is_expected.to delete_file '/etc/nova/nova-compute.conf' }
      it { is_expected.to enable_service 'libvirtd-tcp.socket' }
      it { is_expected.to start_service 'libvirtd-tcp.socket' }
      it { expect(chef_run.link('/usr/bin/qemu-system-x86_64')).to link_to('/usr/libexec/qemu-kvm') }
      it { is_expected.to create_cookbook_file '/etc/libvirt/libvirtd.conf' }
      it { expect(chef_run.cookbook_file('/etc/libvirt/libvirtd.conf')).to notify('service[libvirtd]').to(:restart) }
      it { is_expected.to enable_service 'libvirtd' }
      it { is_expected.to start_service 'libvirtd' }
      it { is_expected.to run_execute('Deleting default libvirt network').with(command: 'virsh net-destroy default') }
      it { is_expected.to include_recipe 'osl-openstack::compute_common' }

      it do
        is_expected.to create_template('/etc/nova/nova.conf').with(
          owner: 'root',
          group: 'nova',
          mode: '0640',
          sensitive: true,
          variables: nova_conf_vars
        )
      end

      it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/^force_raw_images = true$/) }
      it { is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/cpu_mode = none/) }
      it { is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/disk_cachemodes = file=writeback/) }
      it do
        is_expected.to render_file('/etc/nova/nova.conf').with_content { |c|
          expect(c[/^\[neutron\]\n(?:[^\[].*\n)*/]).to_not include('disk_allocation_ratio')
        }
      end
      it_behaves_like 'oslo messaging config', '/etc/nova/nova.conf'
      # nova-manage and any tokenless admin context need [cinder] credentials;
      # API-driven calls forward the user's token and never reach this
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/^auth_type = password$/) }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/^\[cinder\]$/) }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/^username = nova$/) }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/^\[upgrade_levels\]\n#.*\ncompute = auto$/) }
      it { is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/^\[api\]$|auth_strategy/) }
      it do
        is_expected.to render_file('/etc/nova/nova.conf').with_content(
          %r{^\[privsep_osbrick\]\n#.*\nhelper_command = sudo nova-rootwrap /etc/nova/rootwrap.conf privsep-helper --config-file /etc/nova/nova.conf$}
        )
      end
      it { is_expected.to modify_user('nova').with(shell: '/bin/sh') }

      it do
        is_expected.to create_osl_systemd_unit_drop_in('ulimit').with(
          content: {
            'Service' => {
              'LimitNOFILE' => 1048576,
            },
          },
          unit_name: 'openstack-nova-compute.service'
        )
      end

      it { is_expected.to run_ruby_block 'wait for keystone VIP before starting nova-compute' }
      it { is_expected.to enable_service 'openstack-nova-compute' }
      it { is_expected.to start_service 'openstack-nova-compute' }
      it { expect(chef_run.service('openstack-nova-compute')).to subscribe_to('template[/etc/nova/nova.conf]').on(:restart) }
      it { is_expected.to enable_service 'libvirt-guests' }
      it { is_expected.to start_service 'libvirt-guests' }
      it { is_expected.to install_package 'ksmtuned' }
      it do
        is_expected.to create_template('/etc/ksmtuned.conf').with(
          variables: {
            ksm: {
              'npages_max' => 2500,
              'thres_coef' => 25,
              'monitor_interval' => 30,
            },
          }
        )
      end
      it { expect(chef_run.template('/etc/ksmtuned.conf')).to notify('service[ksmtuned]').to(:restart) }
      it { is_expected.to enable_service 'ksm' }
      it { is_expected.to start_service 'ksm' }
      it { is_expected.to enable_service 'ksmtuned' }
      it { is_expected.to start_service 'ksmtuned' }

      shared_examples 'no KSM in a guest' do
        it { is_expected.to_not install_package 'ksmtuned' }
        it { is_expected.to_not create_template '/etc/ksmtuned.conf' }
        it { is_expected.to_not enable_service 'ksm' }
        it { is_expected.to_not start_service 'ksm' }
        it { is_expected.to_not enable_service 'ksmtuned' }
        it { is_expected.to_not start_service 'ksmtuned' }
      end

      context 'AMD guest' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['virtualization']['role'] = 'guest'
            node.automatic['dmi']['processor']['manufacturer'] = 'AMD'
          end.converge(described_recipe)
        end

        it_behaves_like 'no KSM in a guest'
        it { is_expected.to install_kernel_module('kvm_amd').with(options: %w(nested=1)) }
      end

      it { is_expected.to install_kernel_module('kvm_intel').with(options: %w(nested=1)) }
      it { is_expected.to include_recipe 'osl-openstack::network' }
      it { is_expected.to include_recipe 'osl-openstack::telemetry_compute' }
      it { is_expected.to upgrade_package 'osuosl-openstack-cinder' }
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
          key: [OPENSTACK_SECRETS['compute']['nova_public_key']],
          dir_path: '/var/lib/nova/.ssh'
        )
      end
      it do
        is_expected.to add_osl_ssh_key('nova_migration_key').with(
          content: OPENSTACK_SECRETS['compute']['nova_migration_key'],
          key_name: 'id_rsa',
          user: 'nova',
          dir_path: '/var/lib/nova/.ssh'
        )
      end
      it do
        is_expected.to create_file('/var/lib/nova/.ssh/config_hpnssh').with(
          content: "Host *\n  Port 2222\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n",
          user: 'nova',
          group: 'nova',
          mode: '600'
        )
      end
      it do
        is_expected.to create_file('/var/lib/nova/.ssh/config').with(
          content: "Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  ProxyCommand /usr/bin/hpnssh -F /var/lib/nova/.ssh/config_hpnssh -W %h:2222 %h\n",
          user: 'nova',
          group: 'nova',
          mode: '600'
        )
      end
      it do
        is_expected.to enable_logrotate_app('var_log_ceph').with(
          path: '"/var/log/ceph"',
          frequency: 'daily',
          rotate: 0,
          maxage: 30,
          options: %w(
            copytruncate
            missingok
            notifempty
          )
        )
      end
      it { is_expected.to_not add_osl_repos_centos_kmods 'osl-openstack' }
      it { is_expected.to_not upgrade_package 'kernel' }

      context 'aarch64' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['kernel']['machine'] = 'aarch64'
          end.converge(described_recipe)
        end

        it { is_expected.to_not include_recipe 'yum-osuosl::virt' }

        it do
          is_expected.to install_package %w(
            device-mapper
            device-mapper-multipath
            guestfs-tools
            libguestfs-rescue
            libvirt
            python3-libguestfs
            qemu-kvm
            qemu-kvm-device-display-virtio-gpu
            qemu-kvm-device-display-virtio-gpu-pci
            sg3_utils
            sysfsutils
            virt-win-reg
          )
        end
      end

      context 'ppc64le' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['kernel']['machine'] = 'ppc64le'
          end.converge(described_recipe)
        end
        before do
          allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:kernel_module_available?).with('kvm_hv').and_return(true)
        end

        it { is_expected.to install_kernel_module('kvm_hv') }
        it { is_expected.to load_kernel_module('kvm_hv') }
        it { is_expected.to_not install_kernel_module('kvm_intel') }
        it { is_expected.to_not install_kernel_module('kvm_amd') }

        context 'qemu guest' do
          cached(:chef_run) do
            ChefSpec::SoloRunner.new(pltfrm) do |node|
              node.automatic['kernel']['machine'] = 'ppc64le'
              node.automatic['cpu']['hypervisor_vendor'] = 'KVM'
              node.automatic['cpu']['machine'] = 'CHRP IBM pSeries (emulated by qemu)'
            end.converge(described_recipe)
          end

          it_behaves_like 'no KSM in a guest'
          it { is_expected.to_not install_kernel_module('kvm_hv') }
          it { is_expected.to_not load_kernel_module('kvm_hv') }
        end

        it do
          is_expected.to install_package %w(
            device-mapper
            device-mapper-multipath
            guestfs-tools
            libguestfs-rescue
            libvirt
            python3-libguestfs
            qemu-kvm
            qemu-kvm-device-display-virtio-gpu
            qemu-kvm-device-display-virtio-gpu-pci
            sg3_utils
            sysfsutils
            virt-win-reg
          )
        end
        it { is_expected.to install_package 'kernel-kvm' }
        it { is_expected.to_not add_osl_repos_centos_kmods 'osl-openstack' }
        context 'power10' do
          cached(:chef_run) do
            ChefSpec::SoloRunner.new(pltfrm) do |node|
              node.automatic['kernel']['machine'] = 'ppc64le'
              node.automatic['cpu']['model_name'] = 'POWER10 (raw), altivec supported'
              node.automatic['cpu']['hypervisor_vendor'] = 'pHyp'
            end.converge(described_recipe)
          end
          it { is_expected.to add_osl_repos_centos_kmods('osl-openstack').with(kernel: '6.18') }
          it { is_expected.to upgrade_package 'kernel' }
          it { is_expected.to_not install_package 'kernel-kvm' }
          it { is_expected.to install_kernel_module('kvm_hv') }
          it { is_expected.to load_kernel_module('kvm_hv') }

          context 'before rebooting into the kmods kernel' do
            cached(:chef_run) do
              ChefSpec::SoloRunner.new(pltfrm) do |node|
                node.automatic['kernel']['machine'] = 'ppc64le'
                node.automatic['cpu']['model_name'] = 'POWER10 (raw), altivec supported'
                node.automatic['cpu']['hypervisor_vendor'] = 'pHyp'
              end.converge(described_recipe)
            end
            before do
              allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:kernel_module_available?).with('kvm_hv').and_return(false)
            end
            it { is_expected.to upgrade_package 'kernel' }
            it { is_expected.to_not install_kernel_module('kvm_hv') }
            it { is_expected.to_not load_kernel_module('kvm_hv') }
          end
          it { is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/force_raw_images = false/) }
          it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/cpu_mode = none/) }
          it { is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/disk_cachemodes = file=writeback/) }
        end
      end

      context 'region2 w/o ceph' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.merge(
            step_into: %w(osl_openstack_client osl_openstack_openrc)
          )) do |node|
            node.automatic['fqdn'] = 'node1.testing.osuosl.org'
          end.converge(described_recipe)
        end

        include_context 'region2_stubs'

        it { is_expected.to_not include_recipe 'osl-ceph' }
        it { is_expected.to_not create_osl_ceph_config 'default' }
        it { is_expected.to_not upgrade_package 'osuosl-openstack-cinder' }
        it { is_expected.to_not create_osl_ceph_keyring 'cinder' }
        it { is_expected.to_not create_osl_ceph_keyring 'cinder-backup' }
        it { is_expected.to_not create_directory '/var/run/ceph/guests' }
        it { is_expected.to_not create_directory '/var/log/ceph' }
        it { is_expected.to_not modify_group 'ceph-compute' }

        it do
          is_expected.to create_template('/root/openrc').with(
            mode: '0750',
            sensitive: true,
            variables: {
              endpoint: 'controller.testing.osuosl.org',
              pass: 'admin',
              region: 'RegionTwo',
            }
          )
        end

        it do
          expect(chef_run.group('ceph-compute')).to_not \
            notify('service[openstack-nova-compute]').to(:restart).immediately
        end
        it do
          expect(chef_run.group('ceph-compute')).to_not notify('service[libvirtd]').to(:restart).immediately
        end
        it { is_expected.to_not create_template '/var/chef/cache/secret.xml' }
        it { is_expected.to_not run_execute 'virsh secret-define --file /var/chef/cache/secret.xml' }
        it { is_expected.to_not run_execute 'update virsh ceph secret' }
        it { is_expected.to_not delete_file '/var/chef/cache/secret.xml' }

        it do
          is_expected.to create_template('/etc/nova/nova.conf').with(
            owner: 'root',
            group: 'nova',
            mode: '0640',
            sensitive: true,
            variables: nova_conf_vars(region2: true)
          )
        end
        it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/force_raw_images = false/) }
        it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/disk_cachemodes = file=writeback/) }
      end
    end
  end
end
