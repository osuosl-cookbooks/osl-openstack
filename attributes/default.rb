# osl-openstack default attributes

# Include Fedora attribute fixes that aren't in upstream
case platform
when 'fedora'
  # osl-openstack cookbook attributes
  default['osl-openstack']['openpower']['yum']['repo-key'] = 'http://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl'
  default['osl-openstack']['openpower']['yum']['uri'] = 'http://ftp.osuosl.org/pub/osl/repos/yum/openpower/f20/ppc64'
  default['osl-openstack']['openpower']['kernel_version'] = '3.16.0-1.fc20.ppc64'
  # openstack-* cookbook attributes
  default['openstack']['compute']['platform']['dbus_service'] = 'dbus'
  default['openstack']['db']['python_packages']['mysql'] = [ 'MySQL-python' ]
  default['openstack']['yum']['uri'] = "http://repos.fedorapeople.org/repos/openstack/openstack-#{node['openstack']['release']}/fedora-20"
  default['openstack']['yum']['repo-key'] = "https://github.com/redhat-openstack/rdo-release/raw/master/RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
  # Fix for rsyslog to not pipe to /dev/xconsole
  default['rsyslog']['default_facility_logs'] = {
    '*.info;mail.none;authpriv.none;cron.none' => "#{node['rsyslog']['default_log_dir']}/messages",
    'authpriv.*' => "#{node['rsyslog']['default_log_dir']}/secure",
    'mail.*' => "-#{node['rsyslog']['default_log_dir']}/maillog",
    'cron.*' => "#{node['rsyslog']['default_log_dir']}/cron",
    '*.emerg' => '*',
    'uucp,news.crit' => "#{node['rsyslog']['default_log_dir']}/spooler",
    'local7.*' => "#{node['rsyslog']['default_log_dir']}/boot.log"
  }
when 'centos'
  default['openstack']['yum']['uri'] = "http://repos.fedorapeople.org/repos/openstack/openstack-#{node['openstack']['release']}/epel-6"
  default['openstack']['yum']['repo-key'] = "https://github.com/redhat-openstack/rdo-release/raw/master/RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
end

case node['kernel']['machine']
when "ppc64"
  default['modules']['modules'] = [ 'kvm_hv' ]
end
