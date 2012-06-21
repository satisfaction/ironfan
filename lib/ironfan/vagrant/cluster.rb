#
#   Portions Copyright (c) 2012 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

require 'ironfan/vagrant/facet'
require 'ironfan/vagrant/server'
require 'ironfan/vagrant/server_slice'

module Ironfan
  module Vagrant

    class Cluster < Ironfan::Cluster

      def initialize(*args)
        super(:vagrant, *args)
      end

      def new_facet(*args)
        f = Ironfan::Vagrant::Facet.new(*args)
        f.cloud(:vagrant)   # set the cloud provider, or later bare cloud calls will fail
        f
      end

      def discover!
        @aws_instance_hash = {}
        super
        discover_volumes!
      end

      def discover_volumes!
        servers.each(&:discover_volumes!)
      end

      def discover_addresses!
        servers.each(&:discover_addresses!)
      end

      protected

      def fog_servers
        @fog_servers = @cloud.fog_servers.select{|fs| fs.key_name == cluster_name.to_s && (fs.state != "terminated") }
      end

    end

  end
end