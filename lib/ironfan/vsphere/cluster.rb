#
#   Copyright (c) 2012 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

require 'ironfan'
require 'ironfan/vsphere/facet'
require 'ironfan/vsphere/server'
require 'ironfan/vsphere/server_slice'

module Ironfan
  module Vsphere
    class Cluster < Ironfan::Cluster

      def initialize(*args)
        super(:vsphere, *args)
      end

      def new_facet(*args)
        Ironfan::Vsphere::Facet.new(*args)
      end

      def servers
        svrs = @facets.map{ |name, facet| facet.servers.to_a }
        Ironfan::Vsphere::ServerSlice.new(self, svrs.flatten)
      end

    end
  end
end