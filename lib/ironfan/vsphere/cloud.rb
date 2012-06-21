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

require 'ironfan/cloud'

module Ironfan
  module Vsphere
    class Cloud < Ironfan::Cloud::Base
      def initialize *args
        super *args
        name :vsphere
      end

      def self.fog_connection
        @@fog_connection ||= Ironfan::Vsphere::IaasProvider.new
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