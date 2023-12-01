require_relative '../../spec_helper'

describe 'osl-openstack::block_storage' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['cluster_name'] = 'x86'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to add_osl_repos_openstack 'block-storage' }
      it { is_expected.to create_osl_openstack_client 'block-storage' }
      it { is_expected.to accept_osl_firewall_openstack 'block-storage' }
      it { is_expected.to include_recipe 'osl-openstack::block_storage_common' }
      it { is_expected.to_not include_recipe 'osl-openstack::_block_ceph' }
      it { is_expected.to enable_service 'openstack-cinder-volume' }
      it { is_expected.to start_service 'openstack-cinder-volume' }
      it do
        expect(chef_run.service('openstack-cinder-volume')).to \
          subscribe_to('template[/etc/cinder/cinder.conf]').on(:restart)
      end

      context 'ceph' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['cluster_name'] = 'x86'
            node.normal['osl-openstack']['ceph']['volume'] = true
          end.converge(described_recipe)
        end

        it { is_expected.to include_recipe 'osl-openstack::_block_ceph' }
        it { is_expected.to install_package 'openstack-cinder' }
        it do
          is_expected.to modify_group('ceph-block').with(
            group_name: 'ceph',
            append: true,
            members: %w(cinder)
          )
        end
        it do
          expect(chef_run.group('ceph-block')).to \
            notify('service[openstack-cinder-volume]').to(:restart).immediately
        end
        it { is_expected.to create_osl_ceph_keyring('cinder').with(key: 'AQAjbr1aWv+aNBAAoGfqrwX9iSdNmtuvUkwGhA==') }
        it do
          is_expected.to create_osl_ceph_keyring('cinder-backup').with(key: 'AQAxbr1ac4ToKhAAeO6+h90GcsukzHicUNvfLg==')
        end
        it do
          expect(chef_run.osl_ceph_keyring('cinder')).to \
            notify('service[openstack-cinder-volume]').to(:restart).immediately
        end
      end
    end
  end
end
