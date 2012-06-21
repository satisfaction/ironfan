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

require 'ironfan/virtualbox/facet'
require 'ironfan/virtualbox/server'
require 'ironfan/virtualbox/server_slice'

module Ironfan
  module VirtualBox

    class Cluster < Ironfan::Cluster

      def initialize(*args)
        super(:virtualbox, *args)
      end

      def new_facet(*args)
        f = Ironfan::VirtualBox::Facet.new(*args)
        f.cloud(:virtualbox)   # set the cloud provider, or later bare cloud calls will fail
        f
      end

      def discover_addresses!
        servers.each(&:discover_addresses!)
      end

      protected

      def fog_servers
        @fog_servers = @cloud.fog_servers.select{|fs| fs.name == cluster_name.to_s && (fs.status != "terminated") }
      end

    end

  end
end