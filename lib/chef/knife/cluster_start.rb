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

        exit_status = 0
        if config[:bootstrap]
          exit_status = bootstrap_cluster(cluster_name, target)
          display(target)
        end

        section("Starting cluster completed.")
        return exit_status
        # END
      end
    end
  end
end
