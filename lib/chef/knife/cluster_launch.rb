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
          task = cloud.fog_connection.create_cluster
          while !task.finished?
            sleep(monitor_interval)
            Chef::Log.debug("Reporting progress of creating cluster vms: #{task.get_progress.inspect}")
            monitor_launch_progress(cluster_name, task.get_progress)
          end
          Chef::Log.debug("result of creating cluster vms: #{task.get_progress.inspect}")
          update_fog_servers(target, task.get_progress.result.servers)

          Chef::Log.debug("Reporting final status of creating cluster VMs")
          monitor_launch_progress(cluster_name, task.get_progress)

          if !task.get_result.succeed?
            die('Creating cluster vms failed. Abort!', CREATE_FAILURE)
          end

          # Sync attached disks info and other info to Chef
          section("Sync'ing to chef after cluster VMs are created")
          target.sync_to_chef
          # END
        end

        ui.info("")
        display(target)

        exit_status = 0
        if config[:bootstrap]
          exit_status = bootstrap_cluster(cluster_name, target)
          display(target)
        end

        section("Launching cluster completed.")

        exit_status
      end

      def display(target)
        super(target, ["Name", "InstanceID", "State", "Flavor", "Image", "Public IP", "Private IP", "Created At"]) do |svr|
          { 'Launchable?' => (svr.launchable? ? "[blue]#{svr.launchable?}[reset]" : '-' ), }
        end
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
