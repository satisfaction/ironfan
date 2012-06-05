require 'ironfan/cloud'

module Ironfan
  module Vsphere
    class Cloud < Ironfan::Cloud::Base
      def initialize *args
        super *args
        name :vsphere
      end

      def fog_connection
        @fog_connection ||= Ironfan::IaasProvider.new
      end

      # Utility methods

      def image_info
        IMAGE_INFO[ [bits, image_name] ] or warn "Make sure to define the machine's bits and image_name. (Have #{[bits, image_name].inspect})"
      end

      def flavor_info
        FLAVOR_INFO[ flavor ] || {} # or raise "Please define the machine's flavor."
      end

      # TODO: we will define flavors for vShpere Cloud, similar to flavors in EC2 Cloud.
      FLAVOR_INFO = {
        'default'    => { :bits => '64-bit' },
      }

      # :bootstrap_distro is the name of bootstrap template file defined in Ironfan
      IMAGE_INFO =  {
        # CentOS 5 x86_64
        %w[ 64-bit  centos5 ] => { :bootstrap_distro => "centos5-vmware" },
      }
    end
  end
end