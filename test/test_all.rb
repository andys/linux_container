require "#{File.dirname(__FILE__)}/../lib/linux_container"

require 'minitest/autorun'

class TestLinuxContainer < MiniTest::Unit::TestCase
  def self.startup
    $sshkey = "/tmp/linuxcontainergemtestssh#{$$}"
    `ssh-keygen -q -t rsa -f #{$sshkey} -N ''` unless File.exists?($sshkey)
    $c = LinuxContainer.new(name: 'linuxcontainergemtest', ssh_key_path: $sshkey)
    $c.create
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

  def test_ephemeral
    assert($ec = $c.start_ephemeral)
    assert_match /^linuxcontainergemtest.+/, $ec.name
    assert($ec.wait_for { running? }, 'wait_for running?')
    assert($ec.wait_for { ip }, 'wait_for ip')
    assert($ec.wait_for { sshable? }, 'wait_for sshable?')
    assert_equal "hi\n", $ec.execute('echo hi')
    $ec.stop
    assert($ec.wait_for { !running? }, 'wait_for !running?')
  end
end



MiniTest::Unit.after_tests do
    File.unlink($sshkey) rescue nil
    ($ec.destroy '-f' if $ec) rescue nil
    $c.destroy '-f'
  end
TestLinuxContainer.startup