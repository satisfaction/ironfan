module Ironfan
  module Ec2
    class Facet < Ironfan::Cluster

      def after_cloud_created(attrs)
        create_facet_security_group unless attrs[:no_security_group]
      end

      # Create a security group named for the facet
      # which is friends with everything in the facet
      def create_facet_security_group
        cloud.security_group("#{cluster_name}-#{facet_name}")
      end

    end
  end
end