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
  module VirtualBox
    class ServerSlice < Ironfan::ServerSlice

      #
      # Override VM actions methods defined in parent class
      #

      # FIXME: this is a jumble. we need to pass it in some other way.
      MINIMAL_HEADINGS  = ["Name", "Chef?", "State", "InstanceID", "Public IP", "Created At"].to_set.freeze
      DEFAULT_HEADINGS  = (MINIMAL_HEADINGS + ['Env']).freeze
      EXPANDED_HEADINGS = DEFAULT_HEADINGS + ['Image', 'SSH Key']

      MACHINE_STATE_COLORS  = {
        'running'       => :green,
        'pending'       => :yellow,
        'stopping'      => :magenta,
        'shutting-down' => :magenta,
        'stopped'       => :cyan,
        'terminated'    => :blue,
        'not running'   => :blue,
      }
      def display hh = :default
        headings =
          case hh
          when :minimal  then MINIMAL_HEADINGS
          when :default  then DEFAULT_HEADINGS
          when :expanded then EXPANDED_HEADINGS
          else hh.to_set
          end
        headings += ["Bogus"] if servers.any?(&:bogus?)
        defined_data = servers.map do |svr|
          hsh = {
            "Name"   => svr.fullname,
            "Facet"  => svr.facet_name,
            "Index"  => svr.facet_index,
            "Chef?"  => (svr.chef_node? ? "yes" : "[red]no[reset]"),
            "Bogus"  => (svr.bogus? ? "[red]#{svr.bogosity}[reset]" : ''),
            "Env"    => svr.environment,
          }
          # if (cs = svr.chef_server)
          #   hsh.merge!(
          #     "Env"    => cs.environment,
          #     )
          # end
          if (fs = svr.fog_server)
            hsh.merge!(
              "InstanceID" => (fs.id && fs.id.length > 0) ? fs.id : "???",
              "OS Type"    => fs.os,
              "State"      => "[#{MACHINE_STATE_COLORS[fs.status] || 'white'}]#{fs.status}[reset]",
              "Public IP"  => fs.public_ip_address,
            )
          else
            hsh["State"] = "not exist"
          end

          if block_given?
            extra_info = yield(svr)
            hsh.merge!(extra_info)
            headings += extra_info.keys
          end
          hsh
        end
        if defined_data.empty?
          ui.info "Nothing to report"
        else
          Formatador.display_compact_table(defined_data, headings.to_a)
        end
      end
    end
  end
end