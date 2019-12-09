execute '/root/upgrade.sh' do
  live_stream true
  creates '/root/rocky-upgrade-done'
end
