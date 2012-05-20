require 'chef/knife'
require File.expand_path('../../../ironfan/iaas_layer', File.realpath(__FILE__)) # FIXME

module Ironfan
  module KnifeCommon

    # Exit Status of Knife commands
    SUCCESS ||= 0
    FAILURE ||= 1
    CREATE_FAILURE ||= 2
    BOOTSTRAP_FAILURE ||= 3

    def self.load_deps
      require 'formatador'
      require 'chef/node'
      require 'chef/api_client'
      require 'fog'
    end

    def load_ironfan
      $LOAD_PATH << File.join(Chef::Config[:ironfan_path], '/lib') if Chef::Config[:ironfan_path]
      require 'ironfan'
      $stdout.sync = true
      Ironfan.ui          = self.ui
      Ironfan.chef_config = self.config

      # for-vsphere
      initialize_ironfan_broker
    end

    def initialize_ironfan_broker
      initialize_iaas_provider(config[:from_file])
      save_distro_info(config[:from_file])
    end

    def initialize_iaas_provider(filename)
      Iaas::IaasProvider.init(JSON.parse(File.read(filename))) # initialize IaasProvider
    end

    def save_distro_info(filename)
      Chef::Log.debug("Loading hadoop distro info")
      begin
        cluster_def = JSON.parse(File.read(filename))['cluster_definition']
        distro_name = cluster_def['distro']
        distro_repo = cluster_def['distro_map']
        distro_repo['id'] = distro_name
      rescue StandardError => e
        raise e, "Malformed hadoop distro info in cluster definition file."
      end

      Chef::Log.debug("Saving hadoop distro info to Chef Data Bag: #{distro_repo}")
      data_bag_name = "hadoop_distros"
      databag = Chef::DataBag.load(data_bag_name) rescue databag = nil
      if databag.nil?
        databag = Chef::DataBag.new
        databag.name(data_bag_name)
        databag.save
      end
      databag_item = Chef::DataBagItem.load(distro_name) rescue databag_item = nil
      databag_item ||= Chef::DataBagItem.new
      databag_item.data_bag(data_bag_name)
      databag_item.raw_data = distro_repo
      databag_item.save
    end

    def cluster_name
      @name_args[0] # FIXME this will fail when @name_args is [clustername-facet-index]
    end

    #
    # A slice of a cluster:
    #
    # @param [String] cluster_name  -- cluster to slice
    # @param [String] facet_name    -- facet to slice (or nil for all in cluster)
    # @param [Array, String] slice_indexes -- servers in that facet (or nil for all in facet).
    #   You must specify a facet if you use slice_indexes.
    #
    # @return [Ironfan::ServerSlice] the requested slice
    def get_slice(slice_string, *args)
      if not args.empty?
        slice_string = [slice_string, args].flatten.join("-")
        ui.info("")
        ui.warn("Please specify server slices joined by dashes and not separate args:\n\n  knife cluster #{sub_command} #{slice_string}\n\n")
      end
      cluster_name, facet_name, slice_indexes = slice_string.split(/[\s\-]/, 3)
      ui.info("Inventorying servers in #{predicate_str(cluster_name, facet_name, slice_indexes)}")
      cluster = Ironfan.load_cluster(cluster_name)
      cluster.resolve!
      cluster.discover!
      cluster.slice(facet_name, slice_indexes)
    end

    def predicate_str(cluster_name, facet_name, slice_indexes)
      [ "#{ui.color(cluster_name, :bold)} cluster",
        (facet_name    ? "#{ui.color(facet_name, :bold)} facet"      : "#{ui.color("all", :bold)} facets"),
        (slice_indexes ? "servers #{ui.color(slice_indexes, :bold)}" : "#{ui.color("all", :bold)} servers")
      ].join(', ')
    end

    # method to nodes should be filtered on
    def relevant?(server)
      server.exists?
    end

    # override in subclass to confirm risky actions
    def confirm_execution(*args)
      # pass
    end

    #
    # Get a slice of nodes matching the given filter
    #
    # @example
    #    target = get_relevant_slice(* @name_args)
    #
    def get_relevant_slice( *predicate )
      full_target = get_slice( *predicate )
      display(full_target) do |svr|
        rel = relevant?(svr)
        { :relevant? => (rel ? "[blue]#{rel}[reset]" : '-' ) }
      end
      full_target.select{|svr| relevant?(svr) }
    end

    # passes target to ClusterSlice#display, will show headings in server slice
    # tables based on the --verbose flag
    def display(target, display_style=nil, &block)
      display_style ||= (config[:verbosity] == 0 ? :default : :expanded)
      target.display(display_style, &block)
    end

    #
    # Put Fog into mock mode if --dry_run
    #
    def configure_dry_run
      if config[:dry_run]
        Fog.mock!
        Fog::Mock.delay = 0
      end
    end

    # Show a pretty progress bar while we wait for a set of threads to finish.
    def progressbar_for_threads(threads)
      section "Waiting for servers:"
      total      = threads.length
      remaining  = threads.select(&:alive?)
      start_time = Time.now
      until remaining.empty?
        remaining = remaining.select(&:alive?)
        if config[:verbose]
          ui.info "waiting for threads to complete: #{total - remaining.length} / #{total}, #{(Time.now - start_time).to_i}s"
          sleep 5
        else
          Formatador.redisplay_progressbar(total - remaining.length, total, {:started_at => start_time })
          sleep 1
        end
      end
      # Collapse the threads
      threads.each(&:join)
      ui.info ''
    end

    def bootstrapper(server, hostname)
      bootstrap = Chef::Knife::Bootstrap.new
      bootstrap.config.merge!(config)

      # load SSH info from knife.rb
      config[:ssh_user] ||= Chef::Config[:knife][:ssh_user]
      config[:ssh_password] ||= Chef::Config[:knife][:ssh_password]

      bootstrap.name_args               = [ hostname ]
      bootstrap.config[:node]           = server
      bootstrap.config[:run_list]       = server.combined_run_list
      bootstrap.config[:ssh_user]       = config[:ssh_user]       || server.cloud.ssh_user
      bootstrap.config[:ssh_password]   = config[:ssh_password]
      bootstrap.config[:attribute]      = config[:attribute]
      bootstrap.config[:identity_file]  = config[:identity_file]  || server.cloud.ssh_identity_file
      bootstrap.config[:distro]         = config[:distro]         || server.cloud.bootstrap_distro
      bootstrap.config[:use_sudo]       = true unless config[:use_sudo] == false
      bootstrap.config[:chef_node_name] = server.fullname
      bootstrap.config[:client_key]     = server.client_key.body  if server.client_key.body

      bootstrap
    end

    def run_bootstrap(node, hostname)
      ret = 0
      bs = bootstrapper(node, hostname)
      if config[:skip].to_s == 'true'
        ui.info "Skipping: bootstrap #{hostname} with #{JSON.pretty_generate(bs.config)}"
      else
        begin
          ret = bs.run
        rescue StandardError => e
          ui.error "Error thrown when bootstrapping #{hostname} : #{e}"
          ui.error e.backtrace.pretty_inspect
          ui.error "Node data is : #{node.pretty_inspect}"
          ret = BOOTSTRAP_FAILURE
        end
      end

      ui.warn "Bootstrapping #{hostname} completed with exit status #{ret.to_s}"
      ret
    end

    def bootstrap_cluster(cluster_name, target)
      start_monitor_bootstrap(cluster_name)
      exit_status = []
      target.cluster.facets.each do |name, facet|
        section("Bootstrapping machines in facet #{name}", :green)
        servers = target.select { |svr| svr.facet_name == facet.name }
        # As each server finishes, configure it
        watcher_threads = servers.parallelize do |svr|
          exit_value = bootstrap_server(svr)
          monitor_bootstrap_progress(svr, exit_value)
          exit_value
        end
        exit_status += watcher_threads.map{ |t| t.join.value }
        ## progressbar_for_threads(watcher_threads) # this bar messes up with normal logs
      end
      Chef::Log.debug("Exit status of bootstrapping cluster: #{exit_status.inspect}")

      exit_status.select{|i| i != SUCCESS}.empty? ? SUCCESS : BOOTSTRAP_FAILURE
    end

    def bootstrap_server(server)
      # Run Bootstrap
      if config[:bootstrap]
        # Test SSH connection
        unless config[:dry_run]
          nil until tcp_test_ssh(server.fog_server.ipaddress) { sleep 3 }
        end
        # Bootstrap
        run_bootstrap(server, server.fog_server.ipaddress)
      else
        return SUCCESS
      end
    end

    def tcp_test_ssh(hostname)
      tcp_socket = TCPSocket.new(hostname, 22)
      readable = IO.select([tcp_socket], nil, nil, 5)
      if readable
        Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
        yield
        true
      else
        false
      end
    rescue Errno::ETIMEDOUT
      false
    rescue Errno::ECONNREFUSED
      sleep 2
      false
    ensure
      tcp_socket && tcp_socket.close
    end

    #
    # Utilities
    #

    def sub_command
      self.class.sub_command
    end

    def confirm_or_exit question, correct_answer
      response = ui.ask_question(question)
      unless response.chomp == correct_answer
        die "I didn't think so.", "Aborting!", 1
      end
      ui.info("")
    end

    #
    # Announce a new section of tasks
    #
    def section(desc, *style)
      style = [:green] if style.empty?
      ui.info(ui.color(desc, *style))
    end

    def die *args
      Ironfan.die(*args)
    end

    module ClassMethods
      def sub_command
        self.to_s.gsub(/^.*::/, '').gsub(/^Cluster/, '').downcase
      end

      def import_banner_and_options(klass, options={})
        options[:except] ||= []
        deps{ klass.load_deps }
        klass.options.sort_by{|k,v| k.to_s}.each do |name, info|
          next if options.include?(name) || options[:except].include?(name)
          option name, info
        end
        options[:description] ||= "#{sub_command} all servers described by given cluster slice"
        banner "knife cluster #{"%-11s" % sub_command} CLUSTER[-FACET[-INDEXES]] (options) - #{options[:description]}"
      end
    end
    def self.included(base)
      base.class_eval do
        extend ClassMethods
      end
    end
  end
end

#
# Override the methods in Chef::Knife::Ssh to return the exit value of SSH command
#
class Chef
  class Knife
    class Ssh < Knife
      def run
        extend Chef::Mixin::Command

        @longest = 0

        configure_attribute
        configure_user
        configure_identity_file
        configure_session

        exit_status = 
        case @name_args[1]
        when "interactive"
          interactive
        when "screen"
          screen
        when "tmux"
          tmux
        when "macterm"
          macterm
        when "csshx"
          csshx
        else
          ssh_command(@name_args[1..-1].join(" "))
        end

        session.close
        exit_status
      end

      def ssh_command(command, subsession=nil)
        exit_status = 0
        subsession ||= session
        command = fixup_sudo(command)
        subsession.open_channel do |ch|
          ch.request_pty
          ch.exec command do |ch, success|
            raise ArgumentError, "Cannot execute #{command}" unless success
            # note: you can't do the stderr calback because requesting a pty
            # squashes stderr and stdout together
            ch.on_data do |ichannel, data|
              print_data(ichannel[:host], data)
              if data =~ /^knife sudo password: /
                ichannel.send_data("#{get_password}\n")
              end
            end
            ch.on_request "exit-status" do |ichannel, data|
              exit_status = data.read_long
            end
          end
        end
        session.loop
        exit_status
      end
    end
  end
end