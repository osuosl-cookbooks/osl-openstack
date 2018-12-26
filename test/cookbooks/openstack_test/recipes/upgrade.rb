execute '/root/upgrade.sh' do
  live_stream true
  creates '/root/ocata-upgrade-done'
end
