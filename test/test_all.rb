at_exit do
  puts "Destroying test containers"
  File.unlink($sshkey) rescue nil
  ($ec.destroy '-f' if $ec) rescue nil
  ($c2.destroy '-f' if $c2) rescue nil
  $c.destroy '-f' if $c
end

require 'minitest/unit'
require "#{File.dirname(__FILE__)}/../lib/linux_container"

class TestLinuxContainer < MiniTest::Unit::TestCase
  def self.startup
    puts "Creating test containers"
    $sshkey = "/tmp/linuxcontainergemtestssh#{$$}"
    `ssh-keygen -q -t rsa -f #{$sshkey} -N ''` unless File.exists?($sshkey)
    $c = LinuxContainer.new(name: 'linuxcontainergemtest', ssh_key_path: $sshkey)
    $c.create(release: 'precise') or raise "Create failed"
  end

  def test_state
    assert_equal 'STOPPED', $c.state
  end

  def test_running
    assert_equal false, $c.running?
  end

  def test_dir
    assert_equal '/var/lib/lxc/linuxcontainergemtest/rootfs/flibble', $c.dir('flibble')
  end

  def test_list
    assert_includes LinuxContainer.all.map(&:name), 'linuxcontainergemtest'
  end

  def test_clone
    $c2 = LinuxContainer.new name: 'linuxcontainergemtest2'
    $c2.clone_from $c.name
    assert_includes LinuxContainer.all.map(&:name), 'linuxcontainergemtest2'
    $c2.destroy('-f')
    refute_includes LinuxContainer.all.map(&:name), 'linuxcontainergemtest2'
  end

  def test_ephemeral
    assert($ec = $c.start_ephemeral)
    assert_match /^linuxcontainergemtest(-temp)?-[_a-zA-Z0-9]+$/, $ec.name
    assert_equal $c.name, $ec.parent_container.name
    assert($ec.wait_for { running? }, 'wait_for running?')
    assert($ec.wait_for { ip }, 'wait_for ip')
    assert($ec.wait_for { sshable? }, 'wait_for sshable?')
    assert_equal "hi\n", $ec.execute('echo hi')
    File.unlink('/tmp/lsb-release') rescue nil
    $ec.scp_from('/etc/lsb-release', '/tmp/lsb-release')
    assert File.exists?('/tmp/lsb-release')
    $ec.stop
    assert($ec.wait_for { !running? }, 'wait_for !running?')
    assert($ec.wait_for { !File.exists?($ec.dir) }, 'wait_for directory deletion')
  end
  
  def test_ephemeral_overlayfs
    assert($ec = $c.start_ephemeral('union-type' => 'overlayfs'))
    assert($ec.wait_for { running? }, 'wait_for running?')
    assert($ec.wait_for { ip }, 'wait_for ip')
    $ec.stop
    assert($ec.wait_for { !running? }, 'wait_for !running?')
  end
  
  def test_bg_execute_failure
    assert_raises(LinuxContainer::ProcessFailed) do
      $c.bg_execute 'false'
      sleep 5
    end
  end

end

TestLinuxContainer.startup
MiniTest::Unit.new.run ARGV
