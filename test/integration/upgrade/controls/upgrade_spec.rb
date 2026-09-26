control 'upgrade' do
  describe file('/root/upgrade.sh') do
    it { should be_executable }
  end
end
