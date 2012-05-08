#
# Author:: Hui Hu (<huh@vmware.com>)
# Copyright:: Copyright (c) 2012 VMware, Inc.
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
require File.expand_path('cluster_launch', File.dirname(__FILE__))

class Chef
  class Knife
    class ClusterCreate < ClusterLaunch
      import_banner_and_options(Ironfan::Script)

      deps do
        require 'json'
        Chef::Knife::ClusterLaunch.load_deps
      end

      banner "knife cluster create      CLUSTER (options) - Creates a cluster file according to the cluster definition in a json file specified by --fromfile param."
      [ :dry_run, :force, :bootstrap,
        :ssh_port, :ssh_user, :ssh_password, :identity_file, :use_sudo,
        :prerelease, :bootstrap_version, :template_file, :distro,
        :bootstrap_runs_chef_client, :host_key_verify
      ].each do |name|
        option name, Chef::Knife::ClusterLaunch.options[name]
      end

      def run
        load_ironfan
        die(banner) if @name_args.empty?
        configure_dry_run

        # load SSH info from knife.rb
        config[:ssh_user] ||= Chef::Config[:knife][:ssh_user]
        config[:ssh_password] ||= Chef::Config[:knife][:ssh_password]

        section("Creating cluster file", :green)
        Ironfan.create_cluster(config[:from_file], config[:yes])

        # Call ClusterLaunch.run
        super
      end
    end
  end
end
