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

require File.expand_path('ironfan_script',       File.dirname(__FILE__))

class Chef
  class Knife
    class ClusterStart < Ironfan::Script
      import_banner_and_options(Ironfan::Script)

      deps do
        require 'time'
        require 'socket'
        Chef::Knife::ClusterBootstrap.load_deps
      end

      option :bootstrap,
        :long        => "--[no-]bootstrap",
        :description => "Also bootstrap the launched node (default is NOT to bootstrap)",
        :boolean     => true,
        :default     => false

      def relevant?(server)
        server.startable?
      end

      def perform_execution(target)
        # BEGIN for-vsphere
=begin ironfan's code
        section("Starting machines")
        super(target)
        section("Announcing Chef nodes as started")
        target.send(:delegate_to_servers, :announce_as_started)
=end
        section("Powering on VMs of cluster #{cluster_name}")
        task = Ironfan.fog_connection.start_cluster
        begin
          sleep(MONITOR_INTERVAL)
          Chef::Log.debug("progress of starting cluster: #{task.get_progress.inspect}")
          monitor_start_progress(cluster_name, task.get_progress, !config[:bootstrap])
        end while !task.finished?

        update_fog_servers(target, task.get_progress.result.servers)
        display(target)

        if !task.get_result.succeed?
          die('Powering on VMs of cluster failed. Abort!', 1)
        end

        exit_values = []
        if config[:bootstrap]
          exit_values = bootstrap_cluster(cluster_name, target)
        end
        Chef::Log.debug("exit values of starting cluster: #{exit_values}")

        section("Starting cluster completed.")
        return exit_values.select{|i| i != 0}.empty? ? 0 : 3
        # END
      end

      def bootstrap_cluster(cluster_name, target)
        start_monitor_bootstrap(cluster_name)
        watcher_threads = []
        target.cluster.facets.each do |name, facet|
          section("Bootstrapping machines in facet #{name}", :green)
          servers = target.select { |svr| svr.facet_name == facet.name }
          # As each server finishes, configure it
          watcher_threads = servers.parallelize do |svr|
            exit_value = bootstrap_server(svr)
            monitor_bootstrap_progress(svr, exit_value)
            exit_value
          end
          ## progressbar_for_threads(watcher_threads)
        end
        watcher_threads.map{ |t| t.join.value }
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
          return 0
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
    end
  end
end
