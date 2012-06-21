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
    class Server < Ironfan::Server

      #
      # Override VM attributes methods defined in base class
      #
      def created?
        in_cloud? && (not ['terminated', 'shutting-down'].include?(fog_server.state))
      end

      def running?
        has_cloud_state?('running')
      end

      def startable?
        has_cloud_state?('stopped')
      end

      # FIXME -- this will break on some edge case where a bogus node is
      # discovered after everything is resolved!
      def default_availability_zone
        cloud.default_availability_zone
      end

      #
      # Override VM actions methods defined in base class
      #
      def sync_to_cloud
        step "Syncing to cloud"
        attach_volumes
        create_tags
        associate_public_ip
      end

      def sync_volume_attributes
        super
        composite_volumes.each do |vol_name, vol|
          chef_node.normal[:volumes] ||= Mash.new
          chef_node.normal[:volumes][vol_name] = vol.to_mash.compact
        end
      end

      def create_server
        return true if created?
        fog_create_server
      end

      def create_tags
        return unless created?
        step("  labeling servers and volumes")
        fog_create_tags(fog_server, self.fullname, tags)
        composite_volumes.each do |vol_name, vol|
          if vol.fog_volume
            fog_create_tags(vol.fog_volume, vol.desc,
              { "server" => self.fullname, "name" => "#{name}-#{vol.name}", "device" => vol.device, "mount_point" => vol.mount_point, "cluster" => cluster_name, "facet"   => facet_name, "index"   => facet_index, })
          end
        end
      end

      #
      # Methods that handle Fog actions
      #

      def fog_create_server
        step(" creating cloud server", :green)
        lint_fog
        launch_desc = fog_launch_description
        Chef::Log.debug(JSON.pretty_generate(launch_desc))
        safely do
          @fog_server = @cloud.fog_connection.servers.create(launch_desc)
        end
      end

      def lint_fog
        unless cloud.image_id then raise "No image ID found: nothing in Chef::Config[:irtualbox_image_info] for AZ #{self.default_availability_zone} flavor #{cloud.flavor} backing #{cloud.backing} image name #{cloud.image_name}, and cloud.image_id was not set directly. See https://github.com/infochimps-labs/ironfan/wiki/machine-image-(AMI)-lookup-by-name - #{cloud.list_images}" end
        unless cloud.image_id then cloud.list_flavors ; raise "No machine flavor found" ; end
      end

      def fog_launch_description
        user_data_hsh =
          if client_key.body then cloud.user_data.merge({ :client_key     => client_key.body })
        else                    cloud.user_data.merge({ :validation_key => cloud.validation_key }) ; end
        #
        description = {
          :image_id             => cloud.image_id,
          :flavor_id            => cloud.flavor,
          :vpc_id               => cloud.vpc,
          :subnet_id            => cloud.subnet,
          :groups               => cloud.security_groups.keys,
          :key_name             => cloud.keypair.to_s,
          # Fog does not actually create tags when it creates a server.
          :tags                 => {
            :cluster            => cluster_name,
            :facet              => facet_name,
            :index              => facet_index, },
          :user_data            => JSON.pretty_generate(user_data_hsh),
          :block_device_mapping => block_device_mapping,
          :availability_zone    => default_availability_zone,
          :monitoring           => cloud.monitoring,
          # :disable_api_termination => cloud.permanent,
          # :instance_initiated_shutdown_behavior => instance_initiated_shutdown_behavior,
        }
        if needs_placement_group?
          ui.warn "1.3.1 and earlier versions of Fog don't correctly support placement groups, so your nodes will land willy-nilly. We're working on a fix"
          description[:placement] = { 'groupName' => cloud.placement_group.to_s }
        end
        description
      end

      def ensure_placement_group
        return unless needs_placement_group?
        pg_name = cloud.placement_group.to_s
        desc = "placement group #{pg_name} for #{self.fullname} (vs #{Ironfan.placement_groups.inspect}"
        return if Ironfan.placement_groups.include?(pg_name)
        safely do
          step("  creating #{desc}", :blue)
          unless_dry_run{ Ironfan.fog_connection.create_placement_group(pg_name, 'cluster') }
          Ironfan.placement_groups[pg_name] = { 'groupName' => pg_name, 'strategy' => 'cluster' }
        end
        pg_name
      end

      def needs_placement_group?
        cloud.flavor_info[:placement_groupable]
      end

      #
      # Takes key-value pairs and idempotently sets those tags on the cloud machine
      #
      def fog_create_tags(fog_obj, desc, tags)
        tags['Name'] ||= tags['name'] if tags.has_key?('name')
        tags_to_create = tags.reject{|key, val| fog_obj.tags[key] == val.to_s }
        return if tags_to_create.empty?
        step("  tagging #{desc} with #{tags_to_create.inspect}", :green)
        tags_to_create.each do |key, value|
          Chef::Log.debug( "tagging #{desc} with #{key} = #{value}" )
          safely do
            @cloud.fog_connection.tags.create({
                :key => key, :value => value.to_s, :resource_id => fog_obj.id })
          end
        end
      end

      def fog_address
        address_str = self.cloud.public_ip or return
        @cloud.fog_addresses[address_str]
      end

      def associate_public_ip
        address = self.cloud.public_ip
        return unless self.in_cloud? && address
        desc = "elastic ip #{address} for #{self.fullname}"
        if (fog_address && fog_address.server_id) then check_server_id_pairing(fog_address, desc) ; return ; end
        safely do
          step("  assigning #{desc}", :blue)
          cloud.fog_connection.associate_address(self.fog_server.id, address)
        end
      end

      def check_server_id_pairing thing, desc
        return unless thing && thing.server_id && self.in_cloud?
        type_of_thing = thing.class.to_s.gsub(/.*::/,"")
        if thing.server_id != self.fog_server.id
          ui.warn "#{type_of_thing} mismatch: #{desc} is on #{thing.server_id} not #{self.fog_server.id}: #{thing.inspect.gsub(/\s+/m,' ')}"
          false
        else
          Chef::Log.debug("#{type_of_thing} paired: #{desc}")
          true
        end
      end

      def set_instance_attributes
        return unless self.in_cloud? && (not self.cloud.permanent.nil?)
        desc = "termination flag #{permanent?} for #{self.fullname}"
        # the EC2 API does not surface disable_api_termination as a value, so we
        # have to set it every time.
        safely do
          step("  setting #{desc}", :blue)
          unless_dry_run do
            Ironfan.fog_connection.modify_instance_attribute(self.fog_server.id, {
                'DisableApiTermination.Value' => permanent?, })
          end
          true
        end
      end

    end
  end
end