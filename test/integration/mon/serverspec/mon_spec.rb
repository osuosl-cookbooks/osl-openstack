require 'serverspec'

set :backend, :exec

# Should match the number of VCPUs the VMs use
t_cpu = 4

load_thres = if %w(ppc64 ppc64le).include?(os[:arch])
               "-w #{t_cpu * 5 + 10},#{t_cpu * 5 + 5},#{t_cpu * 5} " \
               "-c #{t_cpu * 8 + 10},#{t_cpu * 8 + 5},#{t_cpu * 8}"
             else
               "-w #{t_cpu * 2 + 10},#{t_cpu * 2 + 5},#{t_cpu * 2} " \
               "-c #{t_cpu * 4 + 10},#{t_cpu * 4 + 5},#{t_cpu * 4}"
             end

describe file('/etc/nagios/nrpe.d/check_load.cfg') do
  its(:content) do
    should match(%r{command\[check_load\]=/usr/lib64/nagios/plugins/check_load \
#{load_thres}})
  end
end
