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