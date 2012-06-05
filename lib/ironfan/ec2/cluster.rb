require 'ironfan/ec2/facet'
require 'ironfan/ec2/server'
require 'ironfan/ec2/server_slice'

module Ironfan
  module Ec2

    class Cluster < Ironfan::Cluster

      def initialize(*args)
        super(:ec2, *args)
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

      def after_cloud_created(attrs)
        create_cluster_security_group unless attrs[:no_security_group]
      end

      # Create a security group named for the cluster
      # which is friends with everything in the cluster
      def create_cluster_security_group
        clname = self.name # put it in scope
        cloud.security_group(clname){ authorize_group(clname) }
      end

      protected

      def fog_servers
        @fog_servers = @cloud.fog_servers.select{|fs| fs.key_name == cluster_name.to_s && (fs.state != "terminated") }
      end

    end

  end
end