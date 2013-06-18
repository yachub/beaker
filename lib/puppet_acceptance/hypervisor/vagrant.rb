module PuppetAcceptance 
  class Vagrant < PuppetAcceptance::Hypervisor

    # Return a random mac address
    #
    # @return [String] a random mac address
    def randmac
      "080027" + (1..3).map{"%0.2X"%rand(256)}.join
    end

    def initialize(hosts_to_provision, options, config)
      require 'tempfile'
      set_defaults(hosts_to_provision)
      @options = options
      @config = config
      @logger = options[:logger]
      self.ssh_confs  = {}
      @temp_files = []

      #HACK HACK HACK - add checks here to ensure that we have box + box_url
      #generate the VagrantFile
      @vagrant_file = ''
      hosts_to_provision.each do |name|
        host_info = @config['HOSTS'][name]
        @vagrant_file = "Vagrant::Config.run do |c|\n"
        @vagrant_file << "  c.vm.define '#{name}' do |v|\n"
        @vagrant_file << "    v.vm.host_name = '#{name}'\n"
        @vagrant_file << "    v.vm.box = '#{host_info['box']}'\n"
        @vagrant_file << "    v.vm.box_url = '#{host_info['box_url']}'\n" unless host_info['box_url'].nil?
        @vagrant_file << "    v.vm.base_mac = '#{randmac}'\n"
        @vagrant_file << "  end\n"
        @logger.debug "created Vagrantfile for VagrantHost #{name}"
      end
      @vagrant_file << "end\n"
      f = File.open("Vagrantfile", 'w') 
      f.write(@vagrant_file)
      f.close()
      system("vagrant up")
      @logger.debug "construct listing of ssh-config per vagrant box name"
      hosts_to_provision.each do |name|
        f = Tempfile.new("#{name}")
        config = `vagrant ssh-config #{name}`
        f.write(config)
        f.rewind
        self.ssh_confs[name] = {:config => f.path()}
        @temp_files << f
      end
      self.user = 'vagrant'
    end

    def cleanup
      @logger.debug "removing temporory ssh-config files per-vagrant box"
      @temp_files.each do |f|
        f.close()
      end
      @logger.notify "Destroying vagrant boxes"
      system("vagrant destroy --force")
    end

  end
end
