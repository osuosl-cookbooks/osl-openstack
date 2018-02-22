def ceph_demo_fsid
  require 'inifile'
  wait_for_file('/etc/ceph-docker/ceph.conf')
  ceph_conf = IniFile.load('/etc/ceph-docker/ceph.conf')
  ceph_conf['global']['fsid']
end

def ceph_demo_admin_key
  require 'inifile'
  wait_for_file('/etc/ceph-docker/ceph.client.admin.keyring')
  admin_client = IniFile.load('/etc/ceph-docker/ceph.client.admin.keyring')
  admin_client['client.admin']['key']
end

def ceph_demo_mon_key
  require 'inifile'
  wait_for_file('/etc/ceph-docker/ceph.mon.keyring')
  mon_client = IniFile.load('/etc/ceph-docker/ceph.mon.keyring')
  mon_client['mon.']['key']
end

def ceph_demo_glance_key
  require 'inifile'
  wait_for_file('/etc/ceph/ceph.client.glance.keyring')
  glance_client = IniFile.load('/etc/ceph/ceph.client.glance.keyring')
  glance_client['client.glance']['key']
end

def ceph_demo_cinder_key
  require 'inifile'
  wait_for_file('/etc/ceph/ceph.client.cinder.keyring')
  cinder_client = IniFile.load('/etc/ceph/ceph.client.cinder.keyring')
  cinder_client['client.cinder']['key']
end

def ceph_demo_cinder_backup_key
  require 'inifile'
  wait_for_file('/etc/ceph/ceph.client.cinder-backup.keyring')
  cinder_backup_client = IniFile.load('/etc/ceph/ceph.client.cinder-backup.keyring')
  cinder_backup_client['client.cinder-backup']['key']
end

def wait_for_file(file)
  sleep(1) until File.exist?(file)
end
