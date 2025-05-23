module OSLOpenstack
  module Cookbook
    module Helpers
      include Chef::Mixin::ShellOut
      require 'fog/openstack'

      def os_secrets
        data_bag_item('openstack', node['osl-openstack']['databag_item'])
      end

      def openstack_rabbitmq_user?(user)
        cmd = shell_out!('rabbitmqctl -q list_users')
        cmd.stdout.match(/^#{user}/)
      end

      def openstack_rabbitmq_permissions?(user)
        cmd = shell_out!('rabbitmqctl -q list_permissions')
        cmd.stdout.match(/^#{user}\s+\.\*\s+\.\*\s+\.\*/)
      end

      def openstack_rabbitmq_repo
        case node['platform_version'].to_i
        when 8
          'https://ftp.osuosl.org/pub/osl/vault/$releasever-stream/messaging/$basearch/rabbitmq-38'
        when 9
          'https://centos-stream.osuosl.org/SIGs/$releasever-stream/messaging/$basearch/rabbitmq-38'
        end
      end

      def openstack_services
        {
          'block-storage' => 'cinder',
          'compute_api' => 'nova_api',
          'compute_cell0' => 'nova_cell0',
          'compute' => 'nova',
          'dashboard' => 'horizon',
          'identity' => 'keystone',
          'image' => 'glance',
          'network' => 'neutron',
          'orchestration' => 'heat',
          'placement' => 'placement',
          'telemetry' => 'ceilometer',
        }
      end

      def openstack_python_bin
        case node['platform_version'].to_i
        when 8, 9
          '/usr/bin/python3'
        end
      end

      def openstack_python_lib
        case node['platform_version'].to_i
        when 8
          '/usr/lib/python3.6'
        when 9
          '/usr/lib/python3.9'
        end
      end

      def openstack_client_pkg
        case node['platform_version'].to_i
        when 8, 9
          %w(
            openstack-selinux
            python3-openstackclient
          )
        end
      end

      def openstack_compute_controller_pkgs
        case node['platform_version'].to_i
        when 8, 9
          %w(
            openstack-nova-api
            openstack-nova-conductor
            openstack-nova-novncproxy
            openstack-nova-scheduler
            openstack-placement-api
            python3-osc-placement
          )
        end
      end

      def openstack_compute_pkgs
        case node['platform_version'].to_i
        when 8
          %w(
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
        when 9
          pkgs =
            %w(
              device-mapper
              device-mapper-multipath
              libguestfs-rescue
              libvirt
              openstack-nova-compute
              python3-libguestfs
              qemu-kvm
              qemu-kvm-device-display-virtio-gpu
              qemu-kvm-device-display-virtio-gpu-pci
              sg3_utils
              sysfsutils
              virt-win-reg
            )
          pkgs << 'qemu-kvm-device-display-virtio-vga' if intel?
          pkgs.sort!
        end
      end

      def openstack_transport_url
        m = os_secrets['messaging']

        "rabbit://#{m['user']}:#{m['pass']}@#{m['endpoint']}:5672"
      end

      def openstack_database_connection(service)
        s = os_secrets
        suffix = s['database_server']['suffix']
        db_name = "#{openstack_services[service]}_#{suffix}"
        db_user = "#{s[service]['db']['user']}_#{suffix}"
        db_host = s['database_server']['endpoint']

        "mysql+pymysql://#{db_user}:#{s[service]['db']['pass']}@#{db_host}:3306/#{db_name}"
      end

      def openstack_vxlan_ip(controller)
        node_type = controller ? 'controller' : 'compute'
        vxlan = os_secrets['network']['vxlan_interface']
        vxlan_interface = vxlan[node_type][node['fqdn']] || vxlan[node_type]['default']
        vxlan_addrs = node['network']['interfaces'][vxlan_interface]

        if vxlan_addrs.nil? || vxlan_addrs['addresses'].empty?
          # Fall back to localhost if the interface has no IP
          '127.0.0.1'
        else
          address = vxlan_addrs['addresses'].find do |_, attrs|
            attrs['family'] == 'inet'
          end
          if address.nil?
            '127.0.0.1'
          else
            address[0]
          end
        end
      end

      def openstack_pci_alias
        pci_alias = os_secrets['compute']['pci_alias']
        if pci_alias
          pci_alias[node['fqdn']] || nil
        end
      end

      def openstack_pci_passthrough_whitelist
        pci_passthrough_whitelist = os_secrets['compute']['pci_passthrough_whitelist']
        if pci_passthrough_whitelist
          pci_passthrough_whitelist[node['fqdn']] || nil
        end
      end

      def openstack_local_storage_compute
        local_storage = os_secrets['compute']['local_storage']
        if local_storage
          local_storage[node['fqdn']] || false
        else
          false
        end
      end

      def openstack_cinder_disabled?
        cinder_disabled = os_secrets['compute']['cinder_disabled']
        if cinder_disabled
          cinder_disabled[node['fqdn']] || false
        else
          false
        end
      end

      def openstack_local_storage_image
        local_storage = os_secrets['image']['local_storage']
        if local_storage
          local_storage[node['fqdn']] || false
        else
          false
        end
      end

      def openstack_physical_interface_mappings(controller)
        node_type = controller ? 'controller' : 'compute'
        int_mappings = []
        physical_interface_mappings = os_secrets['network']['physical_interface_mappings']

        physical_interface_mappings.each do |int|
          interface = int[node_type][node['fqdn']] || int[node_type]['default']
          int_mappings.push("#{int['name']}:#{interface}") unless interface == 'disabled'
        end

        int_mappings
      end

      def openstack_power8?
        node.read('cpu', 'model_name').to_s.match?(/POWER8/)
      end

      def openstack_power10?
        node.read('cpu', 'model_name').to_s.match?(/POWER10/)
      end

      # OpenStack API helpers
      def os_conn
        s = os_secrets
        params = {
          openstack_auth_url: "https://#{s['identity']['endpoint']}:5000/v3",
          openstack_username: 'admin',
          openstack_api_key: s['users']['admin'],
          openstack_project_name: 'admin',
          openstack_domain_name: 'default',
        }

        count = 0
        begin
          @connection_cache ||= Fog::OpenStack::Identity.new(params)
        rescue
          count += 1
          Chef::Log.warn("Unable to connect to controller, retry ##{count}")
          sleep(1)
          retry unless count > 10
        end
      end

      def os_role(new_resource)
        os_conn.roles.find { |r| r.name == new_resource.role_name }
      end

      def os_service(new_resource)
        os_conn.services.find do |s|
          s.name == new_resource.service_name
        end
      end

      def os_domain(new_resource)
        os_conn.domains.find { |u| u.id == new_resource.domain_name } ||
          os_conn.domains.find { |u| u.name == new_resource.domain_name }
      end

      def os_endpoint(new_resource)
        service = os_service(new_resource)
        raise "service_name #{new_resource.service_name} not found" if service.nil?
        os_conn.endpoints.find do |e|
          e.service_id == service.id && e.interface == new_resource.interface && e.region == new_resource.region
        end
      end

      def os_project(new_resource)
        # return if new_resource.project_name.nil?
        domain = os_domain(new_resource)
        os_conn.projects.find do |p|
          (p.name == new_resource.project_name) && (domain ? p.domain_id == domain.id : {})
        end
      end

      def os_user(new_resource)
        domain = os_domain(new_resource)
        os_conn.users.find_by_name(
          new_resource.user_name,
          domain ? { domain_id: domain.id } : {}
        ).first
      end

      def os_user_grant_role(new_resource)
        project = os_project(new_resource)
        role = os_role(new_resource)
        user = os_user(new_resource)
        raise "project_name #{new_resource.project_name} not found" if project.nil?
        raise "role #{new_resource.role_name} not found" if role.nil?
        raise "user #{new_resource.user_name} not found" if user.nil?
        (user.projects.find { |p| p['name'] == new_resource.project_name })
      end

      def os_user_grant_domain(new_resource)
        role = os_role(new_resource)
        user = os_user(new_resource)
        raise "role #{new_resource.role_name} not found" if role.nil?
        raise "user #{new_resource.user_name} not found" if user.nil?
        user.check_role role.id
      end

      private

      def safe_dig(hash, *keys)
        keys.reduce(hash) do |acc, key|
          acc.is_a?(Hash) ? acc[key] : nil
        end
      end
    end
  end
end
Chef::DSL::Recipe.include ::OSLOpenstack::Cookbook::Helpers
Chef::Resource.include ::OSLOpenstack::Cookbook::Helpers
