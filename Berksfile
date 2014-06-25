source "https://api.berkshelf.com"

# OSL Base deps
cookbook "base", git: "git@github.com:osuosl-cookbooks/base"
cookbook "omnibus_updater"
cookbook "aliases", git: "git@github.com:osuosl-cookbooks/aliases"
cookbook "firewall", git: "git@github.com:osuosl-cookbooks/firewall"
cookbook "nagios", git: "git@github.com:osuosl-cookbooks/nagios"
cookbook "monitoring", git: "git@github.com:osuosl-cookbooks/monitoring"
cookbook "munin"
cookbook "osl-munin", git: "git@github.com:osuosl-cookbooks/osl-munin"
cookbook "osl-nginx", git: "git@github.com:osuosl-cookbooks/osl-nginx"
cookbook "osl-apache", git: "git@github.com:osuosl-cookbooks/osl-apache"
cookbook "runit", "1.5.10"
cookbook "yum", "3.0.0"
cookbook "apt", "~> 2.2"

# Openstack deps
cookbook "mysql", "~> 4.1"
%w(openstack-block-storage openstack-common
openstack-object-storage openstack-ops-database openstack-ops-messaging
openstack-orchestration openstack-telemetry).each do |cb|
  cookbook cb,
    github: "stackforge/cookbook-#{cb}",
    branch: "stable/havana"
end
%w(openstack-identity openstack-image openstack-network).each do |cb|
  cookbook cb,
    github: "osuosl-cookbooks/cookbook-#{cb}",
    branch: "havana/databag-fixes"
end
cookbook "openstack-compute",
  github: "osuosl-cookbooks/cookbook-openstack-compute",
  branch: "havana/ppc64-misc-fixes"
cookbook "openstack-dashboard",
  github: "osuosl-cookbooks/cookbook-openstack-dashboard",
  branch: "havana/ssl_fix"

metadata
