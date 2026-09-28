module OSLOpenstack
  module Cookbook
    module Helpers
      include Chef::Mixin::ShellOut

      # Module-level so the data bag and keystone connection survive across
      # the per-resource action-class instances Chef creates.
      class << self
        attr_accessor :secrets_cache, :conn_cache
      end

      def self.collection_cache
        @collection_cache ||= {}
      end

      # Reset all module-level caches. Call between ChefSpec examples so
      # cached state doesn't leak across tests.
      def self.reset_cache!
        @secrets_cache = nil
        @conn_cache = nil
        @collection_cache = {}
      end

      def install_fog_openstack_gem
        return if gem_installed?('fog-openstack')
        declare_resource(:package, 'gcc') { compile_time(true) }

        declare_resource(:chef_gem, 'fog-openstack') do
          version '~> 1.1'
          compile_time true
        end
      end

      def os_secrets
        OSLOpenstack::Cookbook::Helpers.secrets_cache ||=
          data_bag_item('openstack', node['osl-openstack']['databag_item'])
      end

      def openstack_rabbitmq_user?(user)
        openstack_shell_match?('rabbitmqctl -q list_users', /^#{Regexp.escape(user)}\s/)
      end

      # nil checks the default vhost; pass a name for a per-cloud vhost.
      def openstack_rabbitmq_permissions?(user, vhost = nil)
        flag = vhost ? " -p #{vhost}" : ''
        openstack_shell_match?("rabbitmqctl -q list_permissions#{flag}", /^#{Regexp.escape(user)}\s+\.\*\s+\.\*\s+\.\*/)
      end

      def openstack_rabbitmq_vhost?(vhost)
        openstack_shell_match?('rabbitmqctl -q list_vhosts', /^#{Regexp.escape(vhost)}\s*$/)
      end

      def openstack_rabbitmq_policy?(vhost, policy)
        openstack_shell_match?("rabbitmqctl -q list_policies -p #{vhost}", /^#{Regexp.escape(vhost)}\s+#{Regexp.escape(policy)}\s/)
      end

      def openstack_rabbitmq_plugin?(plugin)
        openstack_shell_match?('rabbitmq-plugins -q list -e -m', /^#{Regexp.escape(plugin)}$/)
      end

      def openstack_rabbitmq_user_tag?(user, tag)
        openstack_shell_match?('rabbitmqctl -q list_users', /^#{Regexp.escape(user)}\s+\[[^\]]*#{Regexp.escape(tag)}/)
      end

      def openstack_rabbitmq_firewall_ports
        %w(amqp rabbitmq_mgt)
      end

      # Config files every ceilometer daemon restarts on
      def openstack_ceilometer_config_resources
        %w(
          template[/etc/ceilometer/ceilometer.conf]
          template[/etc/ceilometer/pipeline.yaml]
          cookbook_file[/etc/ceilometer/polling.yaml]
        )
      end

      # Config changes every nova controller daemon restarts on
      def openstack_nova_config_resources
        [
          'delete_lines[remove dhcpbridge]',
          'delete_lines[remove force_dhcp_release]',
          'template[/etc/nova/nova.conf]',
        ]
      end

      # Messaging SIG selects version by subdir: EL9 uses rabbitmq-38
      # (3.9.x), EL10 only ships rabbitmq-4 (4.x).
      def openstack_rabbitmq_repo
        case node['platform_version'].to_i
        when 9
          'https://centos-stream.osuosl.org/SIGs/$releasever-stream/messaging/$basearch/rabbitmq-38'
        when 10
          'https://centos-stream.osuosl.org/SIGs/$releasever-stream/messaging/$basearch/rabbitmq-4'
        end
      end

      # Join the primary's Mnesia cluster; isolated brokers strand RPC replies
      # that come back through the other node.
      def openstack_rabbitmq_join_cluster(primary_node_name)
        Chef::Log.info("Joining RabbitMQ cluster with primary '#{primary_node_name}'.")
        shell_out!('rabbitmqctl stop_app')
        shell_out!("rabbitmqctl join_cluster #{primary_node_name}")
        shell_out!('rabbitmqctl start_app')
      rescue Mixlib::ShellOut::ShellCommandFailed => e
        Chef::Log.error("RabbitMQ join_cluster failed: #{e.message}")
        shell_out('rabbitmqctl start_app')
        raise 'Failed to join RabbitMQ cluster; see chef logs.'
      end

      # True when this node should join the primary's cluster: it isn't
      # the primary itself and isn't already a member.
      def openstack_rabbitmq_join_needed?(primary_node_name)
        # Compare short hostnames exactly ("rabbit@mq1.bak.osuosl.org" ->
        # "mq1"); substring matching would conflate mq1 with mq10.
        primary_short_hostname = primary_node_name.split('@', 2).last.split('.', 2).first
        return false if primary_short_hostname == node['hostname']
        # rabbitmqctl 3.8 doesn't accept --format json on cluster_status;
        # if the primary's node name shows up, we're already clustered.
        cluster_status = shell_out('rabbitmqctl cluster_status')
        cluster_status.error!
        !cluster_status.stdout.include?(primary_node_name)
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
        '/usr/bin/python3'
      end

      # The osuosl-openstack-* venvs are built with the platform python3
      def openstack_python_version
        '3.9'
      end

      def openstack_venv(service)
        "/opt/openstack/#{service}"
      end

      def openstack_python_sitelib(service)
        "#{openstack_venv(service)}/lib/python#{openstack_python_version}/site-packages"
      end

      def openstack_client_pkg
        %w(osuosl-openstack-cli)
      end

      def openstack_compute_controller_pkgs
        %w(
          osuosl-openstack-nova-controller
          osuosl-openstack-placement
        )
      end

      def openstack_compute_pkgs
        pkgs = %w(
          device-mapper
          device-mapper-multipath
          guestfs-tools
          libguestfs-rescue
          libvirt
          osuosl-openstack-nova-compute
          python3-libguestfs
          qemu-kvm
          qemu-kvm-device-display-virtio-gpu
          qemu-kvm-device-display-virtio-gpu-pci
          sg3_utils
          sysfsutils
          virt-win-reg
        )
        pkgs << 'qemu-kvm-device-display-virtio-vga' if intel?
        pkgs.sort
      end

      def openstack_auth_endpoint
        os_secrets['identity']['endpoint']
      end

      # Template variables every service config needs for oslo.messaging
      def openstack_messaging_template_vars
        {
          rabbit_quorum_queue: openstack_rabbit_quorum_queue?,
          rabbit_tls: openstack_rabbit_tls?,
          rabbit_ssl_ca_file: openstack_rabbit_ssl_ca_file,
          transport_url: openstack_transport_url,
        }
      end

      def openstack_transport_url
        m = os_secrets['messaging']
        user = m['user']
        pass = m['pass']
        port = openstack_rabbit_tls? ? 5671 : 5672
        hosts = Array(m['endpoint']).sort.map { |endpoint| "#{user}:#{pass}@#{endpoint}:#{port}" }.join(',')
        # messaging.vhost is the URL path; absent or '/' = the default
        # vhost, a name like 'x86' isolates that cloud on the tier.
        vhost = m['vhost'].to_s
        vhost = '' if vhost == '/'
        "rabbit://#{hosts}/#{vhost}"
      end

      def openstack_memcached_endpoints
        Array(os_secrets['memcached']['endpoint']).sort
      end

      def openstack_memcached_servers
        openstack_memcached_endpoints.join(',')
      end

      # tooz sentinel backend_url for the valkey coordination tier, or nil
      # without one; see docs/COORDINATION_TIER.md for the yoga tooz limits.
      def openstack_coordination_url
        c = safe_dig(os_secrets, 'coordination')
        return unless c
        first, *fallbacks = Array(c['endpoint']).sort
        args = ["sentinel=#{c['service_name'] || 'oslocks'}"]
        args += fallbacks.map { |host| "sentinel_fallback=#{host}:26379" }
        args << "db=#{c['db'] || 0}"
        "redis://:#{c['pass']}@#{first}:26379?#{args.join('&')}"
      end

      # Per-host bind address so HAProxy can hold the VIP on the same port;
      # '*' on single-controller clouds.
      def openstack_api_listen_ip
        safe_dig(os_secrets, 'ha', 'api_listen_ip', node['fqdn']) || '*'
      end

      # Address local healthchecks use to reach this node's APIs directly,
      # bypassing the VIP.
      def openstack_local_api_endpoint
        safe_dig(os_secrets, 'ha', 'api_listen_ip', node['fqdn']) || node['ipaddress']
      end

      # HA clouds terminate TLS on haproxy and serve plain HTTP behind it;
      # single-controller clouds keep TLS on Apache.
      def openstack_tls_on_haproxy?
        !!safe_dig(os_secrets, 'ha')
      end

      # Quorum queues are fixed at declaration, so flip this only once the
      # full cluster is up (see docs/HA_MIGRATION.md).
      def openstack_rabbit_quorum_queue?
        !!safe_dig(os_secrets, 'messaging', 'quorum_queues')
      end

      # Connect to RabbitMQ over TLS (AMQPS 5671); set messaging.tls.
      def openstack_rabbit_tls?
        !!safe_dig(os_secrets, 'messaging', 'tls')
      end

      # CA bundle to verify the broker cert; nil uses the system trust
      # store.
      def openstack_rabbit_ssl_ca_file
        safe_dig(os_secrets, 'messaging', 'ssl_ca_file')
      end

      # Gates the ha recipe's one-time eager start; an inactive or absent
      # unit (or no systemctl at all) reads as not running.
      def haproxy_running?
        shell_out('systemctl is-active --quiet haproxy').exitstatus.zero?
      rescue
        false
      end

      # True when the running kernel ships the module as a loadable file;
      # false for built-in modules and for kernels without it
      def kernel_module_available?(name)
        shell_out('modinfo', '-n', name).exitstatus.zero?
      rescue
        false
      end

      # TCP connect to keystone on the VIP; nova-compute exits at startup if
      # it is unreachable, and the connect also warms the VIP's ARP entry.
      def openstack_keystone_reachable?
        require 'socket'
        require 'timeout'
        Timeout.timeout(5) { TCPSocket.new(openstack_auth_endpoint, 5000).close }
        true
      rescue
        false
      end

      # Wait for keystone before starting compute daemons; raises after the
      # retry budget so a real outage surfaces.
      def openstack_wait_for_keystone
        host = openstack_auth_endpoint
        count = 0
        max_attempts = 30
        until openstack_keystone_reachable?
          count += 1
          raise "keystone VIP #{host}:5000 unreachable after #{count} attempts" if count >= max_attempts
          Chef::Log.warn("Waiting for keystone VIP #{host}:5000 before starting compute daemons (attempt ##{count})")
          sleep([2 * count, 15].min)
        end
      end

      # Comma-joined glance endpoint URLs for nova/cinder. Accepts either
      # a single string or an array in os_secrets['image']['endpoint'].
      def openstack_image_api_servers
        Array(os_secrets['image']['endpoint']).map { |e| "http://#{e}:9292" }.join(',')
      end

      # APIs HAProxy fronts on the VIP; `tls: true` ones terminate TLS there in
      # HA mode. The exporter (9183) can't bind a listen address, so it isn't.
      def openstack_ha_services
        [
          { name: 'keystone',       port: 5000, tls: true },
          { name: 'glance-api',     port: 9292 },
          { name: 'nova-api',       port: 8774 },
          { name: 'nova-metadata',  port: 8775 },
          { name: 'placement',      port: 8778 },
          { name: 'neutron-server', port: 9696 },
          { name: 'cinder-api',     port: 8776 },
          { name: 'heat-api',       port: 8004 },
          { name: 'heat-cfn',       port: 8000 },
          { name: 'novnc',          port: 6080, tls: true },
          { name: 'horizon-http',   port: 80,  redirect_to_https: true },
          { name: 'horizon-https',  port: 443, balance: 'source', tls: true },
        ]
      end

      def openstack_db_name(service)
        "#{openstack_services[service]}_#{os_secrets['database_server']['suffix']}"
      end

      def openstack_db_user(service)
        "#{os_secrets[service]['db']['user']}_#{os_secrets['database_server']['suffix']}"
      end

      def openstack_database_connection(service)
        s = os_secrets
        db_host = s['database_server']['endpoint']
        "mysql+pymysql://#{openstack_db_user(service)}:#{s[service]['db']['pass']}@#{db_host}:3306/#{openstack_db_name(service)}"
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
            address.first
          end
        end
      end

      def openstack_pci_alias
        safe_dig(os_secrets, 'compute', 'pci_alias', node['fqdn'])
      end

      def openstack_pci_passthrough_whitelist
        safe_dig(os_secrets, 'compute', 'pci_passthrough_whitelist', node['fqdn'])
      end

      def openstack_local_storage_compute
        safe_dig(os_secrets, 'compute', 'local_storage', node['fqdn']) || false
      end

      def openstack_cinder_disabled?
        safe_dig(os_secrets, 'compute', 'cinder_disabled', node['fqdn']) || false
      end

      def openstack_local_storage_image
        safe_dig(os_secrets, 'image', 'local_storage', node['fqdn']) || false
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

      def openstack_power10?
        node.read('cpu', 'model_name').to_s.match?(/POWER10/)
      end

      def openstack_qemu_guest?
        if node['kernel']['machine'] == 'ppc64le'
          node.read('cpu', 'machine').to_s.match?(/qemu/i)
        else
          node['virtualization']['role'] == 'guest'
        end
      end

      # Guest traffic is bridged through the host conntrack table, so 40+
      # VMs per hypervisor outgrow the stock ceiling.
      def openstack_conntrack_max
        safe_dig(os_secrets, 'compute', 'conntrack', 'max') || 2_097_152
      end

      # Stock 432000 (5 days) is excessive and lets dead entries accumulate.
      def openstack_conntrack_tcp_timeout_established
        safe_dig(os_secrets, 'compute', 'conntrack', 'tcp_timeout_established') || 86_400
      end

      # The hashtable is a module parameter and does not scale with the
      # sysctl, so size it off max unless overridden directly.
      def openstack_conntrack_hashsize
        safe_dig(os_secrets, 'compute', 'conntrack', 'hashsize') || openstack_conntrack_max / 4
      end

      # OpenStack API helpers
      def os_conn
        return OSLOpenstack::Cookbook::Helpers.conn_cache if OSLOpenstack::Cookbook::Helpers.conn_cache

        install_fog_openstack_gem
        raise 'fog-openstack Gem missing' unless gem_installed?('fog-openstack')
        require 'fog/openstack' unless defined?(::Fog)

        s = os_secrets
        params = {
          openstack_auth_url: "https://#{openstack_auth_endpoint}:5000/v3",
          openstack_username: 'admin',
          openstack_api_key: s['users']['admin'],
          openstack_project_name: 'admin',
          openstack_domain_name: 'default',
        }

        # Keystone may not be up yet on a fresh bootstrap; retry with backoff
        # and raise the real error instead of returning nil.
        count = 0
        max_attempts = 20
        last_error = nil
        loop do
          begin
            OSLOpenstack::Cookbook::Helpers.conn_cache = Fog::OpenStack::Identity.new(params)
            return OSLOpenstack::Cookbook::Helpers.conn_cache
          rescue => e
            last_error = e
            count += 1
            break if count >= max_attempts
            Chef::Log.warn("Unable to connect to keystone at #{params[:openstack_auth_url]} (#{e.class}: #{e.message}), retry ##{count}")
            sleep([2**count, 30].min)
          end
        end
        raise "Failed to connect to keystone at #{params[:openstack_auth_url]} after #{count} attempts: #{last_error.class}: #{last_error.message}"
      end

      # Memoized keystone collection; resources that create into one must
      # call os_collection_invalidate afterwards.
      def os_collection(name)
        OSLOpenstack::Cookbook::Helpers.collection_cache[name] ||= os_conn.send(name).all
      end

      def os_collection_invalidate(name)
        OSLOpenstack::Cookbook::Helpers.collection_cache.delete(name)
      end

      def os_role(new_resource)
        os_collection(:roles).find { |r| r.name == new_resource.role_name }
      end

      def os_service(new_resource)
        os_collection(:services).find { |s| s.name == new_resource.service_name }
      end

      def os_domain(new_resource)
        os_collection(:domains).find do |d|
          d.id == new_resource.domain_name || d.name == new_resource.domain_name
        end
      end

      def os_endpoint(new_resource)
        service = os_service(new_resource)
        raise "service_name #{new_resource.service_name} not found" if service.nil?
        os_collection(:endpoints).find do |e|
          e.service_id == service.id && e.interface == new_resource.interface && e.region == new_resource.region
        end
      end

      def os_project(new_resource)
        domain = os_domain(new_resource)
        os_collection(:projects).find do |p|
          p.name == new_resource.project_name && (domain.nil? || p.domain_id == domain.id)
        end
      end

      def os_user(new_resource)
        domain = os_domain(new_resource)
        os_collection(:users).find do |u|
          u.name == new_resource.user_name && (domain.nil? || u.domain_id == domain.id)
        end
      end

      def os_user_grant_role(new_resource)
        project = os_project(new_resource)
        role = os_role(new_resource)
        user = os_user(new_resource)
        raise "project_name #{new_resource.project_name} not found" if project.nil?
        raise "role #{new_resource.role_name} not found" if role.nil?
        raise "user #{new_resource.user_name} not found" if user.nil?
        user.projects.find { |p| p['name'] == new_resource.project_name }
      end

      def os_user_grant_domain(new_resource)
        role = os_role(new_resource)
        user = os_user(new_resource)
        raise "role #{new_resource.role_name} not found" if role.nil?
        raise "user #{new_resource.user_name} not found" if user.nil?
        user.check_role role.id
      end

      private

      def openstack_shell_match?(cmd, pattern)
        shell_out!(cmd).stdout.match?(pattern)
      end

      def safe_dig(hash, *keys)
        keys.reduce(hash) do |acc, key|
          case acc
          when Hash, Chef::DataBagItem, Chef::EncryptedDataBagItem
            acc[key]
          end
        end
      end

      def gem_installed?(gem_name)
        !Gem::Specification.find_by_name(gem_name).nil?
      rescue Gem::LoadError
        false
      end
    end
  end
end
Chef::DSL::Recipe.include ::OSLOpenstack::Cookbook::Helpers
Chef::Resource.include ::OSLOpenstack::Cookbook::Helpers
