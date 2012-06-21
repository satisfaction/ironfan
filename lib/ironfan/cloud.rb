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
  module Cloud

    #
    # The goal though is to allow
    #
    # * cloud with no predicate -- definitions that apply to all cloud
    #   providers. If you only use one provider ever nothing stops you from
    #   always saying `cloud`.
    # * Declarations irrelevant to other providers are acceptable and will be ignored
    # * Declarations that are wrong in the context of other providers (a `public_ip`
    #   that is not available) will presumably cause a downstream error -- it's
    #   your responsibility to overlay with provider-correct values.
    # * There are several declarations that *could* be sensibly abstracted, but
    #   are not. Rather than specifying `flavor 'm1.xlarge'`, I could ask for
    #   :ram => 15, :cores => 4 or storage => 1500 and get the cheapest machine
    #   that met or exceeded each constraint -- the default of `:price =>
    #   :smallest` would get me a t1.micro on EC2, a 256MB on
    #   Rackspace. Availability zones could also plausibly be parameterized.
    #
    # @example
    #     # these apply regardless of cloud provider
    #     cloud do
    #       # this makes sense everywhere
    #       image_name            'maverick'
    #
    #       # this is not offered by many providers, and its value is non-portable;
    #       # but if you only run in one cloud there's harm in putting it here
    #       # or overriding it.
    #       public_ip             '1.2.3.4'
    #
    #       # Implemented differently across providers but its meaning is clear
    #       security_group        :nagios
    #
    #       # This is harmless for the other clouds
    #       availability_zones   ['us-east-1d']
    #     end
    #
    #     # these only apply to ec2 launches.
    #     # `ec2` is sugar for `cloud(:ec2)`.
    #     ec2 do
    #       spot_price_fraction   0.4
    #     end
    #
    class Base < Ironfan::DslObject
      has_keys(
        :name, :flavor, :image_name, :image_id, :keypair,
        :chef_client_script, :public_ip, :permanent,
        :user_data)

      attr_accessor :owner

      # The owner is the Ironfan::Cluster or Ironfan::Facet who holds this cloud
      def initialize(owner, *args)
        self.owner = owner
        super(*args)
      end

      # Returns a connection Object which talks to various cloud providers including EC2, vSphere, OpenStack, etc.
      def self.fog_connection
        raise_not_implemented
      end

      def fog_connection
        self.class.fog_connection
      end

      def fog_servers
        return @fog_servers if @fog_servers
        Chef::Log.debug("Using fog to catalog all servers")
        @fog_servers = fog_connection.servers.all
      end

      def fog_addresses
        return @fog_addresses if @fog_addresses
        Chef::Log.debug("Using fog to catalog all addresses")
        @fog_addresses = {}.tap{|hsh| fog_connection.addresses.each{|fa| hsh[fa.public_ip] = fa } }
      end

      def fog_volumes
        return @fog_volumes if @fog_volumes
        Chef::Log.debug("Using fog to catalog all volumes")
        @fog_volumes = fog_connection.volumes
      end

      def fog_keypairs
        return @fog_keypairs if @fog_keypairs
        Chef::Log.debug("Using fog to catalog all keypairs")
        @fog_keypairs = {}.tap{|hsh| fog_connection.key_pairs.each{|kp| hsh[kp.name] = kp } }
      end

      # default values to apply where no value was set
      # @return [Hash] hash of defaults
      def defaults
        reverse_merge!({
          :image_name         => 'natty',
        })
      end

      # The username to ssh with.
      # @return the ssh_user if set explicitly; otherwise, the user implied by the image name, if any; or else 'root'
      def ssh_user(val=nil)
        from_setting_or_image_info :ssh_user, val, 'root'
      end

      # Location of ssh private keys
      def ssh_identity_dir(val=nil)
        set :ssh_identity_dir, File.expand_path(val) unless val.nil?
        @settings.include?(:ssh_identity_dir) ? @settings[:ssh_identity_dir] : Chef::Config.ssh_key_dir
      end

      # SSH identity file used for knife ssh, knife bootstrap and such
      def ssh_identity_file(val=nil)
        set :ssh_identity_file, File.expand_path(val) unless val.nil?
        if @settings.include?(:ssh_identity_file)
          @settings[:ssh_identity_file]
        elsif ssh_identity_dir
          File.join(ssh_identity_dir, "#{keypair}.pem")
        else
          nil
        end
      end

      # ID of the machine image to use.
      # @return the image_id if set explicitly; otherwise, the id implied by the image name
      def image_id(val=nil)
        from_setting_or_image_info :image_id, val
      end

      # Distribution knife should target when bootstrapping an instance
      # @return the bootstrap_distro if set explicitly; otherwise, the bootstrap_distro implied by the image name
      def bootstrap_distro(val=nil)
        from_setting_or_image_info :bootstrap_distro, val, "ubuntu10.04-gems"
      end

      def validation_key
        IO.read(Chef::Config.validation_key) rescue ''
      end

      # The instance price, drawn from the compute flavor's info
      def price
        flavor_info[:price]
      end

      # The instance bitness, drawn from the compute flavor's info
      def bits
        flavor_info[:bits]
      end

    protected
      # If value was explicitly set, use that; if the Chef::Config[:ec2_image_info] implies a value use that; otherwise use the default
      def from_setting_or_image_info(key, val=nil, default=nil)
        @settings[key] = val unless val.nil?
        return @settings[key]  if @settings.include?(key)
        return image_info[key] unless image_info.nil?
        return default       # otherwise
      end
    end

  end
end
