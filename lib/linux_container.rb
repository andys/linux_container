
require 'timeout'
require 'shellwords'
require 'tempfile'

class LinuxContainer
  attr_accessor :name, :username, :ssh_key_path
  attr_writer :ip

  def self.all
    `#{sudo_if_needed} lxc-ls`.lines.map(&:strip).uniq.map {|cname| new(name: cname) }
  end
  
  def initialize(params={})
    params.each {|k,v| instance_variable_set "@#{k}", v }
    @username ||= 'ubuntu'
  end
  
  def state
    info('-s').chomp.split(':').last.strip
  end
  
  def ip
    @ip ||= self.class.get_ip_for(name)
  end

  def create(config={})  # template, hostid, userdata, auth-key, arch, release
    args = (ssh_key_path ? {'auth-key' => "#{ssh_key_path}.pub"} : {}).merge(config).map {|k, v| "--#{k}=#{v}" }
    lxc_execute('create', '-t', config.delete(:template) || 'ubuntu-cloud', '--', *args)
  end
  
  [:start, :stop, :shutdown, :destroy, :execute, :kill, :wait, :cgroup, :ps, :info, :freeze, :unfreeze, :netstat].each do |cmd|
    define_method(cmd) {|*args| lxc_execute(cmd, *args) }
  end

  def clone_from(from, *args)
    fromname = self.class === from ? from.name : from
    lxc_execute('clone', '-o',fromname, *args)
  end

  def start_ephemeral
    args = ['lxc-start-ephemeral','-U','aufs','-u',username,'-o',name]
    logfile = bg_execute(*args)
    newname = nil
    while newname.nil?
      sleep 1
      logfile.rewind
      newname = $1 if logfile.read =~ /^(.*) is running/
     end
    self.class.new(name: newname, ssh_key_path: ssh_key_path, username: username)
  end

  def ssh(cmd)
    raise "cannot ssh without ip" unless ip
    args = ['-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=/dev/null']
    args.push('-i', ssh_key_path) if ssh_key_path
    args.push("#{username}@#{ip}", cmd)
    execute('ssh', *args)
  end 

  def sshable?
    ssh('true') rescue false
  end
  
  def running?
    state == 'RUNNING'
  end

  def dir(subdir=nil)
    "/var/lib/lxc/#{name}/rootfs/#{subdir}"
  end
  
  def wait_for(timeout=300, interval=1, &block)
    Timeout.timeout(timeout) do
      duration = 0
      start = Time.now
      until instance_eval(&block) || duration > timeout
        sleep(interval.to_f)
        duration = Time.now - start
      end
      if duration > timeout
        false
      else
        duration
      end
    end
  end
  
#############################################################################

  def lxc_execute(cmd, *args)
    execute("lxc-#{cmd}", '-n', name, *args)
  end
  
  def execute(*cmd)
    cmdstring = "#{self.class.sudo_if_needed} #{cmd.shift} #{Shellwords.join(cmd)} "
    result = `#{cmdstring} 2>&1`
    raise "command failed: #{cmdstring.inspect}\n#{result}" unless $? == 0
    result
  end
  
  def bg_execute(*cmd)
    logfile = Tempfile.new(self.class.to_s)
    cmdstring = "( #{self.class.sudo_if_needed} #{cmd.shift} #{Shellwords.join(cmd)} >>#{logfile.path} 2>>#{logfile.path} & )"
    system(cmdstring)
    raise "command failed: #{cmdstring.inspect}\n" unless $? == 0
    logfile
  end

  def self.get_ip_for(name)
    File.read('/var/lib/misc/dnsmasq.leases').each_line do |line|
      (timestamp,macaddr,ip,hostname,misc) = line.split(' ')
      return ip if hostname == name
    end
    nil
  end
  
  def self.sudo_if_needed
    'sudo' unless Process.uid == 0
  end
  
end

