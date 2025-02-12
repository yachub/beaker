module Beaker
  module Shared
    # Methods for managing Hosts.
    #- selecting hosts by role (Symbol or String)
    #- selecting hosts by name (String)
    #- adding additional method definitions for selecting by role
    #- executing blocks of code against selected sets of hosts
    module HostManager
      # Find hosts from a given array of hosts that all have the desired role.
      # @param [Array<Host>] hosts The hosts to examine
      # @param [String] desired_role The hosts returned will have this role in their roles list
      # @return [Array<Host>] The hosts that have the desired role in their roles list
      def hosts_with_role(hosts, desired_role = nil)
        hosts.select do |host|
          desired_role.nil? or host['roles'].include?(desired_role.to_s)
        end
      end

      # Find hosts from a given array of hosts that all have the desired name, match against host name,
      # vmhostname and ip (the three valid ways to identify an individual host)
      # @param [Array<Host>] hosts The hosts to examine
      # @param [String] name The hosts returned will have this name/vmhostname/ip
      # @return [Array<Host>] The hosts that have the desired name/vmhostname/ip
      def hosts_with_name(hosts, name = nil)
        hosts.select do |host|
          name.nil? or host.name&.start_with?(name) or host[:vmhostname]&.start_with?(name) or host[:ip]&.start_with?(name)
        end
      end

      # Find a single host with the role provided.  Raise an error if more than one host is found to have the
      # provided role.
      # @param [Array<Host>] hosts The hosts to examine
      # @param [String] role The host returned will have this role in its role list
      # @return [Host] The single host with the desired role in its roles list
      # @raise [ArgumentError] Raised if more than one host has the given role defined, if no host has the
      #                       role defined, or if role = nil since hosts_with_role(nil) returns all hosts.
      def only_host_with_role(hosts, role)
        raise ArgumentError, "role cannot be nil." if role.nil?

        a_host = hosts_with_role(hosts, role)
        if a_host.length == 0
          raise ArgumentError, "There should be one host with #{role} defined!"
        elsif a_host.length > 1
          host_string = (a_host.map { |host| host.name }).join(', ')
          raise ArgumentError, "There should be only one host with #{role} defined, but I found #{a_host.length} (#{host_string})"
        end

        a_host.first
      end

      # Find at most a single host with the role provided.  Raise an error if
      # more than one host is found to have the provided role.
      # @param [Array<Host>] hosts The hosts to examine
      # @param [String] role The host returned will have this role in its role list
      # @return [Host] The single host with the desired role in its roles list
      #                     or nil if no host is found
      # @raise [ArgumentError] Raised if more than one host has the given role defined,
      #   or if role = nil since hosts_with_role(nil) returns all hosts.
      def find_at_most_one_host_with_role(hosts, role)
        raise ArgumentError, "role cannot be nil." if role.nil?

        role_hosts = hosts_with_role(hosts, role)
        case role_hosts.length
        when 0
          nil
        when 1
          role_hosts[0]
        else
          host_string = (role_hosts.map { |host| host.name }).join(', ')
          raise ArgumentError, "There should be only one host with #{role} defined, but I found #{role_hosts.length} (#{host_string})"
        end
      end

      # Execute a block selecting the hosts that match with the provided criteria
      #
      # @param [Array<Host>, Host] hosts The host or hosts to run the provided block against
      # @param [String, Symbol] filter Optional filter to apply to provided hosts - limits by name or role
      # @param [Hash{Symbol=>String}] opts
      # @option opts [Boolean] :run_in_parallel Whether to run on each host in parallel.
      # @param [Block] block This method will yield to a block of code passed by the caller
      #
      # @todo (beaker3.0:BKR-571): simplify return types to Array<Result> only
      #
      # @return [Array<Result>, Result, nil] If an array of hosts has been
      #   passed (after filtering), then either an array of results is returned
      #   (if the array is non-empty), or nil is returned (if the array is empty).
      #   Else, a result object is returned. If filtering makes it such that only
      #   one host is left, then it's passed as a host object (not in an array),
      #   and thus a result object is returned.
      def run_block_on hosts = [], filter = nil, opts = {}, &block
        result = nil
        block_hosts = hosts # the hosts to apply the block to after any filtering
        if filter
          raise ArgumentError, "Unable to sort for #{filter} type hosts when provided with [] as Hosts" if hosts.empty?

          block_hosts = hosts_with_role(hosts, filter) # check by role
          if block_hosts.empty?
            block_hosts = hosts_with_name(hosts, filter) # check by name
          end
          block_hosts = block_hosts.pop if block_hosts.length == 1 # we only found one matching host, don't need it wrapped in an array

        end
        if block_hosts.is_a? Array
          if block_hosts.length > 0
            if run_in_parallel? opts
              # Pass caller[1] - the line that called block_on - for logging purposes.
              result = block_hosts.map.each_in_parallel(caller(2..2).first) do |h|
                run_block_on h, &block
              end
              hosts.each { |host| host.close } # For some reason, I have to close the SSH connection
              # after spawning a process and running commands on a host,
              # or else it gets into a broken state for the next call.
            else
              result = block_hosts.map do |h|
                run_block_on h, &block
              end
            end
          elsif (cur_logger = (logger || @logger))
            # there are no matching hosts to execute against
            # should warn here
            # check if logger is defined in this context
            cur_logger.info "Attempting to execute against an empty array of hosts (#{hosts}, filtered to #{block_hosts}), no execution will occur"
          end
        else
          result = yield block_hosts
        end
        result
      end
    end
  end
end
