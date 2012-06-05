module Ironfan
  module Vsphere

    class Facet < Ironfan::Facet

      def initialize(*args)
        super(*args)
      end

      def new_server(*args)
        Ironfan::Vsphere::Server.new(*args)
      end

    end

  end
end