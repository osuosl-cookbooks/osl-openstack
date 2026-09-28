# The oslo_messaging.conf.erb partial every service template renders
shared_examples 'oslo messaging config' do |path, heartbeat_in_pthread: false|
  it { is_expected.to render_file(path).with_content("[oslo_messaging_rabbit]\nheartbeat_in_pthread = #{heartbeat_in_pthread}\n") }
  it { is_expected.to render_file(path).with_content("[oslo_messaging_notifications]\ndriver = messagingv2\n") }
  it { is_expected.to_not render_file(path).with_content(/^rabbit_quorum_queue/) }
  it { is_expected.to_not render_file(path).with_content(/^ssl = true$/) }
end
