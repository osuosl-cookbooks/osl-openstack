# The oslo_messaging.conf.erb partial every service template renders
shared_examples 'oslo messaging config' do |path, heartbeat_in_pthread: false|
  it { is_expected.to render_file(path).with_content("[oslo_messaging_rabbit]\nheartbeat_in_pthread = #{heartbeat_in_pthread}\n") }
  it { is_expected.to render_file(path).with_content("[oslo_messaging_notifications]\ndriver = messagingv2\n") }
  it { is_expected.to_not render_file(path).with_content(/^rabbit_quorum_queue/) }
  it { is_expected.to_not render_file(path).with_content(/^ssl = true$/) }
end

# openstack_db_sync_on_upgrade: syncs when the package version moved, then records it
shared_examples 'db sync on upgrade' do |svc, syncs|
  it { is_expected.to run_notify_group("#{svc}: package version changed") }
  syncs.each do |s|
    it { expect(chef_run.notify_group("#{svc}: package version changed")).to notify("execute[#{s}]").to(:run).immediately }
  end
  it { is_expected.to nothing_file("/var/lib/osl-openstack/db-sync/#{svc}") }
  it { expect(chef_run.file("/var/lib/osl-openstack/db-sync/#{svc}")).to subscribe_to("execute[#{syncs.last}]").on(:create).immediately }
end

# Chef upgrades the venv RPM, so its services restart when the package changes
shared_examples 'restarts on package upgrade' do |pkg, services|
  services.each do |srv|
    it { expect(chef_run.service(srv)).to subscribe_to("package[#{pkg}]").on(:restart).delayed }
  end
end
