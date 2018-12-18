execute '/root/upgrade.sh' do
  live_stream true
  not_if { ::File.exist?('/root/ocata-upgrade-done') }
  only_if { ::File.exist?('/root/upgrade.sh') }
end
