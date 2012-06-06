#
# Author:: Philip (flip) Kromer (<flip@infochimps.com>)
# Copyright:: Copyright (c) 2011 Infochimps, Inc
# Portions copyright © 2012 VMware, Inc. All rights Reserved.
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

      def relevant?(server)
        server.launchable?
      end

      def perform_execution(target)
        # Pre-populate information in chef
        section("Sync'ing to chef and cloud")
        target.sync_to_cloud
        target.sync_to_chef

        # Launch servers
        section("Creating machines in Cloud", :green)
        ret = target.create_servers
        die('Creating cluster VMs failed. Abort!', CREATE_FAILURE) if !ret

        # Sync attached disks info and other info to Chef
        section("Sync'ing to chef after cluster VMs are created")
        target.sync_to_chef

        exit_status = 0
        if config[:bootstrap]
          display(target)
          exit_status = bootstrap_cluster(cluster_name, target)
        end

        section("Creating cluster completed.")
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
