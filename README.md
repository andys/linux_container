## LinuxContainer gem

This gem is an easy ruby interface to ubuntu linux containers (LXC). It
provides a convenient wrapper for starting Ubuntu Cloud image-based
ephemeral containers.

lxc-start-ephemeral uses "overlay filesystems" to start a cloned container
that uses little disk space. This container disappears when shut down.

    $ gem install linux_container

### Create a new container

    > c = LinuxContainer.new(
        name: 'mycontainer',
        username: 'ubuntu',            # optional for SSH, defaults to ubuntu
        ssh_key_path: '~/.ssh/id_rsa'  # optional
      )

    > c.create(
        template: 'ubuntu-cloud',  # optional, defaults to ubuntu-cloud
        hostid:   'i12345',        # optional, autogenerated
        userdata: 'userdata.txt',  # optional cloud-init user-data script
        auth-key: '~/.ssh/id_rsa', # optional, defaults to ssh_key_path
        arch:     'i686',          # optional, defaults to host arch
        release:  'quantal'        # optional, defaults to host release
      )

    > c.dir('/tmp')
      => "/var/lib/lxc/mycontainer/rootfs/tmp"

### Start container and mess around with it

    > c.start
    > c.state
    > c.running?  
    > c.ip
    > c.wait_for { ip && sshable? }
    > c.ssh 'uptime'
    > c.stop

### Start an ephemeral container cloning an existing container

    > e = c.start_ephemeral
    > e.wait_for { ip && sshable? }
    > e.parent_container
     => #<LinuxContainer:...>


### Clone an existing container and start it in background, with 512M memlimit

    > c2 = LinuxContainer.new(name: 'clonetest')
    > c2.clone_from(c)
    > c2.start('-d', '-s', 'lxc.cgroup.memory.limit_in_bytes=512M')


### Get existing containers

    > LinuxContainer.all
     => [container, container, container, ... ]

### Gracecful shutdown

    > c.shutdown '-t', '120'


### Force shutdown & delete

    > c.destroy '-f'

### SSH a long running command

    > c.ssh('mason build') {|log| print "->#{log}" }

### other commands

    execute, kill, wait, cgroup, ps, info, freeze, unfreeze, netstat

