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

require File.expand_path('ironfan_script', File.dirname(__FILE__))

class Chef
  class Knife
    class ClusterStop < Ironfan::Script
      import_banner_and_options(Ironfan::Script)

      def relevant?(server)
        server.running?
      end

      def perform_execution(target)
        # BEGIN for-vsphere
=begin ironfan's code
        section("Stopping machines")
        super(target)
        section("Announcing Chef nodes as stopped")
        target.send(:delegate_to_servers, :announce_as_stopped)
=end
        section("Shutdowning VMs of cluster #{cluster_name}")
        task = cloud.fog_connection.stop_cluster
        begin
          sleep(MONITOR_INTERVAL)
          Chef::Log.debug("progress of stopping cluster: #{task.get_progress.inspect}")
          monitor_stop_progress(cluster_name, task.get_progress)
        end while !task.finished?

        if !task.get_result.succeed?
          die('Shutdowning VMs of cluster failed. Abort!', 1)
        end

        section("Stopping cluster completed.")
        return 0
        # END
      end

      def confirm_execution(target)
        ui.info "  Unless these nodes are backed by EBS volumes, this will result in loss of all data"
        ui.info "  not saved elsewhere. Even if they are EBS backed, there may still be some data loss."
        confirm_or_exit("Are you absolutely certain that you want to perform this action? (Type 'Yes' to confirm) ", 'Yes')
      end
    end
  end
end
