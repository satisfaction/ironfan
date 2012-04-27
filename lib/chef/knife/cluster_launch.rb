#
# Author:: Philip (flip) Kromer (<flip@infochimps.com>)
# Copyright:: Copyright (c) 2011 Infochimps, Inc
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.expand_path('ironfan_knife_common', File.dirname(__FILE__))
require File.expand_path('cluster_bootstrap',    File.dirname(__FILE__))

class Chef
  class Knife
    class ClusterLaunch < Ironfan::Script
      include Ironfan::KnifeCommon

      deps do
        require 'time'
        require 'socket'
        Chef::Knife::ClusterBootstrap.load_deps
      end

      banner "knife cluster launch      CLUSTER[-FACET[-INDEXES]] (options) - Creates chef node and chef apiclient, pre-populates chef node, and instantiates in parallel their cloud machines. With --bootstrap flag, will ssh in to machines as they become ready and launch the bootstrap process"
      [ :ssh_port, :ssh_user, :ssh_password, :identity_file, :use_sudo,
        :prerelease, :bootstrap_version, :template_file, :distro,
        :bootstrap_runs_chef_client, :host_key_verify
      ].each do |name|
        option name, Chef::Knife::ClusterBootstrap.options[name]
      end

      option :dry_run,
        :long        => "--dry-run",
        :description => "Don't really run, just use mock calls",
        :boolean     => true,
        :default     => false
      option :force,
        :long        => "--force",
        :description => "Perform launch operations even if it may not be safe to do so. Default false",
        :boolean     => true,
        :default     => false

      option :bootstrap,
        :long        => "--[no-]bootstrap",
        :description => "Also bootstrap the launched node (default is NOT to bootstrap)",
        :boolean     => true,
        :default     => false

      def run
        load_ironfan
        die(banner) if @name_args.empty?
        configure_dry_run

        # for-vsphere
        # initialize IaasProvider
        Iaas::IaasProvider.init(JSON.parse(File.read(config[:from_file])))

        cluster_name = @name_args[0] # FIXME this will fail when @name_args is [clustername-facet-index]

        #
        # Load the facet
        #
        full_target = get_slice(*@name_args)
        display(full_target)

        target = full_target
        # FIXME BEGIN vsphere: bypass this logic
        ## target = full_target.select(&:launchable?)
        ## warn_or_die_on_bogus_servers(full_target) unless full_target.bogus_servers.empty?
        # END

        if target.empty?
          section("All servers are running -- not launching any.", :green)
        else
          # Pre-populate information in chef
          section("Sync'ing to chef and cloud")
          target.sync_to_cloud
          target.sync_to_chef

          # Launch servers
          section("Creating machines in Cloud", :green)
          ## target.create_servers(true) # FIXME
          # BEGIN for-vsphere
          start_monitor_launch(cluster_name)
          task = Ironfan.fog_connection.create_cluster
          while !task.finished?
            sleep(MONITOR_INTERVAL)
            Chef::Log.debug("progress of creating cluster: #{task.get_progress.inspect}")
            section("Reporting progress of creating cluster vms", :green)
            monitor_launch_progress(cluster_name, task.get_progress)
          end
          Chef::Log.debug("result of creating cluster vms: #{task.get_progress.inspect}")
          Chef::Log.debug('updating Ironfan::Server.fog_server with value returned by CloudManager')
          fog_servers = task.get_progress.result.servers
          fog_servers.each do |fog_server|
            server_slice = target.servers.find { |svr| svr.fullname == fog_server.name }
            server_slice.servers.fog_server = fog_server if server_slice and server_slice.servers
          end

          if !task.get_result.succeed?
            die('Creating cluster vms failed. Abort!', 1)
          end

          section("Reporting final status of creating cluster vms", :green)
          monitor_launch_progress(cluster_name, task.get_progress)
          # END
        end

        ui.info("")
        display(target)

        start_monitor_bootstrap(cluster_name)
        target = full_target # handle all servers
        target.cluster.facets.each do |name, facet|
          section("Bootstrapping machines in facet #{name}", :green)
          servers = target.select { |svr| svr.facet_name == facet.name }
          # As each server finishes, configure it
          watcher_threads = servers.parallelize do |svr| # FIXME originally use servers.parallelize
            exit_value = perform_after_launch_tasks(svr)
            monitor_bootstrap_progress(svr, exit_value)
            exit_value
          end
          progressbar_for_threads(watcher_threads)
        end

        display(target)
      end

      def display(target)
        super(target, ["Name", "InstanceID", "State", "Flavor", "Image", "Public IP", "Private IP", "Created At"]) do |svr|
          { 'Launchable?' => (svr.launchable? ? "[blue]#{svr.launchable?}[reset]" : '-' ), }
        end
      end

      def perform_after_launch_tasks(server)
        Chef::Log.debug('Entered perform_after_launch_tasks')
        # Wait for node creation on amazon side
        server.fog_server.wait_for{ ready? }

        # Try SSH
        unless config[:dry_run]
          nil until tcp_test_ssh(server.fog_server.ipaddress){ sleep @initial_sleep_delay ||= 10  }
        end

        # Make sure our list of volumes is accurate
        #Ironfan.fetch_fog_volumes
        #server.discover_volumes!
        # Attach volumes, etc
        #server.sync_to_cloud

        # Run Bootstrap
        if config[:bootstrap]
          run_bootstrap(server, server.fog_server.ipaddress)
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

      def warn_or_die_on_bogus_servers(target)
        ui.info("")
        ui.info "Cluster has servers in a transitional or undefined state (shown as 'bogus'):"
        ui.info("")
        display(target)
        ui.info("")
        unless config[:force]
          die(
            "Launch operations may be unpredictable under these circumstances.",
            "You should wait for the cluster to stabilize, fix the undefined server problems",
            "(run \"knife cluster show CLUSTER\" to see what the problems are), or launch",
            "the cluster anyway using the --force option.", "", -2)
        end
        ui.info("")
        ui.info "--force specified"
        ui.info "Proceeding to launch anyway. This may produce undesired results."
        ui.info("")
      end

    end
  end
end
