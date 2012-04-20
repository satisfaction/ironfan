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

        cluster_name = @name_args[0]

        #
        # Load the facet
        #
        full_target = get_slice(*@name_args)
        display(full_target)
        target = full_target.select(&:launchable?)

        warn_or_die_on_bogus_servers(full_target) unless full_target.bogus_servers.empty?

        ## if target.empty? # FIXME
        if false
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
          task = Ironfan.fog_connection.create_cluster
          while !task.finished?
            Chef::Log.debug("progress of creating cluster: #{task.get_progress.inspect}")
            section("Reporting progress of creating cluster vms", :green)
            monitor_launch_progress(cluster_name, task.get_progress)
            sleep(5)
          end
          Chef::Log.debug("result of creating cluster vms: #{task.get_progress.inspect}")
          Chef::Log.debug('updating Ironfan::Server.fog_server with value returned by CloudManager')
          Chef::Log.debug('servers in target:' + target.servers.pretty_inspect)
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
        display(target);

        target = full_target # handle all servers

        start_monitor_bootstrap(cluster_name)

        target.cluster.facets.each do |name, facet|
          section("Bootstrapping machines in facet #{name}", :green)
          servers = target.select { |svr| svr.facet_name == facet.name }
          # As each server finishes, configure it
          watcher_threads = servers.parallelize_with_servers do |svr| # FIXME originally use servers.parallelize
            perform_after_launch_tasks(svr)
          end
          ## progressbar_for_threads(watcher_threads)
          # BEGIN for-vsphere
          section("Report progress of Bootstrapping", :green)
          checked = Hash.new
          while checked.size < watcher_threads.size
            watcher_threads.each do |server, thread|
              if !thread.alive? and !checked[server]
                section("Report result of Bootstrapping VM #{server}")
                monitor_bootstrap_progress(server, thread.value)
                checked[server] = true
              end
            end
          end
          watcher_threads.values.each(&:join)
          # END
        end

        display(target)
      end

      def display(target)
        super(target, ["Name", "InstanceID", "State", "Flavor", "Image", "Public IP", "Private IP", "Created At"]) do |svr|
          { 'Launchable?' => (svr.launchable? ? "[blue]#{svr.launchable?}[reset]" : '-' ), }
        end
      end

      def perform_after_launch_tasks(server)
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

      # Monitor the progress of cluster creation
      def monitor_launch_progress(cluster_name, progress)
        initialize_database

        # update cluster progress
        #cluster_name = progress.cluster_name
        cluster = Ironfan::Database::Cluster.find(:name => cluster_name)
        cluster ||= Ironfan::Database::Cluster.create(:name => cluster_name)
        cluster.finished = false # progress.finished
        cluster.progress = progress.progress / 2
        cluster.status = progress.status
        cluster.succeed = progress.result.succeed
        cluster.instance_num = progress.result.total
        cluster.total = progress.result.total
        cluster.success = progress.result.success
        cluster.failure = progress.result.failure
        cluster.running = progress.result.running
        cluster.save

        return if progress.result.servers.empty?
        # update servers progress within this cluster
        progress.result.servers.each do |vm|
          facet = Ironfan::Database::Facet.find(:name => vm.group_name, :cluster_id => cluster.id)
          facet ||= Ironfan::Database::Facet.create(:name => vm.group_name, :cluster_id => cluster.id)

          server = Ironfan::Database::Server.find(:name => vm.name)
          server ||= Ironfan::Database::Server.new
          server.name = vm.name
          server.facet_id ||= facet.id
          server.cluster_id ||= facet.cluster_id

          server.status = vm.status
          server.ip_address = vm.ip_address
          server.hostname = vm.hostname

          server.finished = false
          server.progress = 0
          server.succeed = false

          server.action_name = 'Create'
          server.action_status = vm.status

          server.created = vm.created
          server.bootstrapped = false
          server.deleted = false

          server.error_code = vm.error_code
          server.error_msg = vm.error_msg

          server.save
        end

        report_progress(cluster_name)
      end

      def start_monitor_bootstrap(cluster_name)
        Chef::Log.debug("start_monitor_bootstrap #{cluster_name}")
        #initialize_database
        require 'ironfan/db/base'
        Ironfan::Database.connect

        cluster = Ironfan::Database::Cluster.find(:name => cluster_name)
        cluster ||= Ironfan::Database::Cluster.create(:name => cluster_name)
        cluster.finished = false # progress.finished
        cluster.progress = 50
        cluster.status = 'Bootstrapping'
        cluster.succeed = false
        cluster.success = 0
        cluster.failure = 0
        cluster.running = cluster.total
        cluster.save

        Ironfan::Database.connect[:servers].filter(:cluster_id => cluster.id).update(:bootstrapped => false)
      end

      def monitor_bootstrap_progress(svr, exit_code)
        cluster_name = svr.cluster_name.to_s
        Chef::Log.debug("monitor_bootstrap_progress #{cluster_name} #{[exit_code, svr]}")
        initialize_database

        cluster = Ironfan::Database::Cluster.find(:name => cluster_name)

        if !exit_code
          server = Ironfan::Database::Server.find(:name => svr.fullname)
          server.bootstrapped = true
          server.save

          cluster.success += 1
        else
          cluster.failure += 1
        end

        cluster.running -= 1
        cluster.progress = (50 + (cluster.success + cluster.failure) * 50.0 / cluster.total).to_i
        cluster.finished = !cluster.running
        cluster.succeed = (cluster.success == cluster.total)
        cluster.save

        report_progress(cluster_name)
      end

      # report cluster provision progress to MessageQueue
      def report_progress(cluster_name)
        Chef::Log.debug("Begin reporting status of cluster #{cluster_name}")
        
        initialize_database

        # generate data in JSON format
        cluster = Ironfan::Database::Cluster.find(:name => cluster_name)
        Chef::Log.debug('Cluster: ' + cluster.inspect)

        data = cluster.as_hash
        data[:cluster_data] = {}
        data[:cluster_data][:groups] = []
        Chef::Log.debug('Facets: ' + cluster.facets.inspect)
        cluster.facets.each do |facet|
          fh = facet.as_hash
          fh[:instances] = []
          Chef::Log.debug('Servers ' + facet.servers.inspect)
          facet.servers.sort_by{ |svr| svr.name }.each do |server|
            fh[:instances] << server.as_hash
          end
          data[:cluster_data][:groups] << fh
        end

        data = JSON.parse(data.to_json) # convert keys from symbol to string
        groups = data['cluster_data']['groups']
        cluster_meta = JSON.parse(File.read(config[:from_file]))['cluster_definition']
        cluster_meta['groups'].each do |meta_group|
          groups.each do |group|
            if meta_group['name'] == group['name']
              meta_group['instances'] = group['instances']
              break
            end
          end
        end
        data['cluster_data'].merge!(cluster_meta)

        # send to MQ
        send_to_mq(data)
        Chef::Log.debug('End reporting cluster status')
      end

      def send_to_mq(data)
        require 'bunny'

        Chef::Log.debug("Sending data to MessageQueue: #{data.pretty_inspect}")

        #b = Bunny.new(:host => '10.141.7.40', :logging => false)
        b = Bunny.new(:host => 'localhost', :logging => false)
        # start a communication session with the amqp server
        b.start

        # create/get exchange
        exch = b.exchange('bddtask', :durable => true)

        # publish message to exchange
        exch.publish(data.to_json, :key => config[:channel])

        # message should now be picked up by the consumer so we can stop
        b.stop
      end

      def initialize_database
        require 'ironfan/db/base'
        Ironfan::Database.connect
      end
    end
  end
end
