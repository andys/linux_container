
require 'timeout'
require 'shellwords'
require 'tempfile'

class LinuxContainer
  attr_accessor :name, :username, :ssh_key_path
  attr_writer :ip

  def self.all
    `#{sudo_if_needed} lxc-ls -1`.lines.map(&:strip).uniq.map {|cname| new(name: cname) }
  end
  
  def self.version
    @version ||= if `lxc-version` =~ /version: (\d+\.\d+)\./i
      $1
    end
  end
    
  def initialize(params={})
    params.each {|k,v| instance_variable_set "@#{k}", v }
    @username ||= 'ubuntu'
  end
  
  def state
    res = `#{self.class.sudo_if_needed} lxc-info -n #{Shellwords.escape name} -s 2>&1`
    res.chomp.split(':').last.to_s.strip 
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

  def start_ephemeral(config={})
    argshash = {'orig' => name, 'user' => username, 'union-type' => 'overlayfs'}.merge!(config)
    args = []
    if self.class.version == '0.8' # ubuntu quantal and older
      args.push '-U', argshash.delete('union-type')
    else # ubuntu raring and newer
      args << '-d'
    end
    args.push *argshash.map {|k, v| "--#{k}=#{v}" }
    
    logfile_path = bg_execute('lxc-start-ephemeral', *args)
    newname = nil
    while newname.nil?
      sleep 1
      newname = $1 || $2 if File.read(logfile_path) =~ /^(.*) is running|lxc-console -n (.*)$/
     end
    self.class.new(name: newname, ssh_key_path: ssh_key_path, username: username)
  end

  def ssh(cmd)
    execute('ssh', *ssh_args, "#{username}@#{ip}", cmd)
  end 

  def scp_to(srcpath, dstpath, *args)
    execute('scp', *args, *ssh_args, srcpath, "#{username}@#{ip}:#{dstpath}")
  end 

  def scp_from(srcpath, dstpath, *args)
    execute('scp', *args, *ssh_args, "#{username}@#{ip}:#{srcpath}", dstpath)
  end 

  def ssh_args
    raise "cannot ssh without ip" unless ip
    args = ['-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=/dev/null']
    args.push('-i', ssh_key_path) if ssh_key_path
    args
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
    cmdstring = "#{self.class.sudo_if_needed} #{cmd.shift} #{Shellwords.join(cmd)}"
    result = `#{cmdstring} 2>&1`
    raise "command failed: #{cmdstring.inspect}\n#{result}" unless $? == 0
    result
  end

  def bg_execute(*cmd)
    logfile_path = "/tmp/lxc_ephemeral_#{Time.now.to_i.to_s(36)}#{$$}#{rand(0x100000000).to_s(36)}.log"
    cmdstring = "( #{self.class.sudo_if_needed} #{cmd.shift} #{Shellwords.join(cmd)} >>#{logfile_path} 2>>#{logfile_path} & )"
    system(cmdstring)
    raise "command failed: #{cmdstring.inspect}\n" unless $? == 0
    logfile_path
  end

  def self.get_ip_for(name)
    fn = ['/var/lib/misc/dnsmasq.lxcbr0.leases', '/var/lib/misc/dnsmasq.leases'].detect {|f| File.readable?(f) }
    File.read(fn).each_line do |line|
      (timestamp,macaddr,ip,hostname,misc) = line.split(' ')
      return ip if hostname == name
    end
    nil
  end
  
  def self.sudo_if_needed
    'sudo' unless Process.uid == 0
  end
  
end

