# Target VM for the Jenkins deployment (Oracle VirtualBox provider).
# The VM is a clean Ubuntu 24.04 box: Apache is NOT installed here,
# it is installed and configured by the Jenkins pipeline (Jenkinsfile).

# Workaround: on recent macOS, Ruby's non-blocking connect (used by Vagrant's
# port-collision check) reports closed localhost ports as open/EINVAL, so
# Vagrant 2.4.x claims every forwarded port is "already in use".
# Use a plain blocking connect instead, which reports ECONNREFUSED correctly.
require "socket"
require "timeout"
require "vagrant/util/is_port_open"
module Vagrant::Util::IsPortOpen
  def is_port_open?(host, port)
    Timeout.timeout(1) { TCPSocket.new(host, port).close }
    true
  rescue Timeout::Error, SystemCallError
    false
  end
end
Vagrant.configure("2") do |config|
  config.vm.box      = "bento/ubuntu-24.04"
  config.vm.hostname = "apache-vm"

  # SSH used by Jenkins (container reaches it via host.docker.internal:2223)
  config.vm.network "forwarded_port", guest: 22, host: 2223, id: "ssh", host_ip: "127.0.0.1"
  # Apache, reachable from the Mac at http://localhost:8081
  config.vm.network "forwarded_port", guest: 80, host: 8081, host_ip: "127.0.0.1"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "apache-vm"
    vb.cpus   = 2
    vb.memory = 1024
  end

  # The VM is treated as a remote host: no shared folder, deploys go over SSH.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Authorize the Jenkins deploy key for the 'vagrant' user (passwordless sudo).
  if File.exist?("keys/jenkins_deploy.pub")
    config.vm.provision "file", source: "keys/jenkins_deploy.pub", destination: "/tmp/jenkins_deploy.pub"
    config.vm.provision "shell", inline: <<-SHELL
      grep -qf /tmp/jenkins_deploy.pub /home/vagrant/.ssh/authorized_keys || \
        cat /tmp/jenkins_deploy.pub >> /home/vagrant/.ssh/authorized_keys
      rm -f /tmp/jenkins_deploy.pub
    SHELL
  end
end
