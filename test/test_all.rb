at_exit do
  puts "Destroying test containers"
  File.unlink($sshkey) rescue nil
  ($ec.destroy '-f' if $ec) rescue nil
  ($c2.destroy '-f' if $c2) rescue nil
  $c.destroy '-f'
end

require 'minitest/autorun'
require "#{File.dirname(__FILE__)}/../lib/linux_container"

class TestLinuxContainer < MiniTest::Unit::TestCase
  def self.startup
    puts "Creating test containers"
    $sshkey = "/tmp/linuxcontainergemtestssh#{$$}"
    `ssh-keygen -q -t rsa -f #{$sshkey} -N ''` unless File.exists?($sshkey)
    $c = LinuxContainer.new(name: 'linuxcontainergemtest', ssh_key_path: $sshkey)
    $c.create or raise "Create failed"
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
    assert_match /^linuxcontainergemtest.+/, $ec.name
    assert($ec.wait_for { running? }, 'wait_for running?')
    assert($ec.wait_for { ip }, 'wait_for ip')
    assert($ec.wait_for { sshable? }, 'wait_for sshable?')
    assert_equal "hi\n", $ec.execute('echo hi')
    $ec.stop
    assert($ec.wait_for { !running? }, 'wait_for !running?')
    assert($ec.wait_for { !File.exists?($ec.dir) }, 'wait_for directory deletion')
  end
end

TestLinuxContainer.startup
