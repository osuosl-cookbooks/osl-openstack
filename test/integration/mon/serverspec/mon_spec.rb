require 'serverspec'

set :backend, :exec

load_thres = if %w(ppc64 ppc64le).include?(os[:arch])
               '-w 14,9,4 -c 18,13,8'
             else
               '-w 12,7,2 -c 14,9,4'
             end

describe file('/etc/nagios/nrpe.d/check_load.cfg') do
  its(:content) do
    should match(%r{command\[check_load\]=/usr/lib64/nagios/plugins/check_load \
#{load_thres}})
  end
end
