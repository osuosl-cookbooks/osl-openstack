require 'serverspec'

set :backend, :exec

load_thres = if %w(ppc64 ppc64le).include?(os[:arch])
               '-w 18,13,8 -c 26,21,16'
             else
               '-w 14,9,4 -c 18,13,8'
             end

describe file('/etc/nagios/nrpe.d/check_load.cfg') do
  its(:content) do
    should match(%r{command\[check_load\]=/usr/lib64/nagios/plugins/check_load \
#{load_thres}})
  end
end
