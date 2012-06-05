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