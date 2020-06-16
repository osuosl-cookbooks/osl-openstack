execute '/root/upgrade.sh' do
  live_stream true
  creates '/root/stein-upgrade-done'
end

%w(mariadb-config mariadb-server).each do |p|
  rpm_package p do
    options '--nodeps'
    action :remove
  end
end
