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

  #
  # A server is a specific (logical) member of a facet within a cluster.
  #
  # It may have extra attributes if it also exists in the Chef server,
  # or if it exists in the real world (as revealed by Fog)
  #
  class Server < Ironfan::ComputeBuilder
    attr_reader   :cluster, :facet, :facet_index, :tags
    attr_accessor :chef_node, :fog_server

    @@all ||= Mash.new

    def initialize facet, idx
      @cluster     = facet.cluster
      @facet       = facet
      @facet_index = idx
      @fullname    = [cluster_name, facet_name, facet_index].join('-')
      super(@fullname)
      @tags = { "name" => name, "cluster" => cluster_name, "facet"   => facet_name, "index" => facet_index, }
      ui.warn("Duplicate server #{[self, facet.name, idx]} vs #{@@all[fullname]}") if @@all[fullname]
      @@all[fullname] = self
    end

    def fullname fn=nil
      @fullname = fn if fn
      @fullname
    end

    def cluster_name
      cluster.name
    end

    def facet_name
      facet.name
    end

    def servers
      Ironfan::ServerSlice.new(cluster, [self])
    end

    def bogosity val=nil
      @settings[:bogosity] = val  if not val.nil?
      return @settings[:bogosity] if not @settings[:bogosity].nil?
      return :bogus_facet         if facet.bogus?
      # return :out_of_range      if (self.facet_index.to_i >= facet.instances)
      false
    end

    def in_cloud?
      !! fog_server
    end

    def in_chef?
      chef_node || chef_client
    end

    def has_cloud_state?(*states)
      in_cloud? && states.flatten.include?(fog_server.state)
    end

    def exists?
      created? || in_chef?
    end

    def created?
      in_cloud?
    end

    def running?
      raise_not_implemented
    end

    def startable?
      raise_not_implemented
    end

    def launchable?
      not created?
    end

    def sshable?
      in_chef?
    end

    def permanent?
      !! self.cloud.permanent
    end

    def killable?
      return false if permanent?
      in_chef? || created?
    end

    def to_s
      super[0..-3] + " chef: #{in_chef? && chef_node.name} fog: #{in_cloud? && fog_server.id}}>"
    end

    #
    # Attributes
    #

    def tag key, value=nil
      if value then @tags[key] = value ; end
      @tags[key]
    end

    def public_hostname
      give_me_a_hostname_from_one_of_these_seven_ways_you_assholes
    end

    def chef_server_url()        Chef::Config.chef_server_url        ; end
    def validation_client_name() Chef::Config.validation_client_name ; end
    def validation_key()         Chef::Config.validation_key         ; end
    def organization()           Chef::Config.organization           ; end
    #
    # Resolve:
    #
    def resolve!
      reverse_merge!(facet)
      reverse_merge!(cluster)
      @settings[:run_list] = combined_run_list

      # create cloud provider
      cloud_name = cluster.cloud.name if cluster.cloud
      cloud_name = facet.cloud.name if facet.cloud
      cloud(cloud_name)
      # merge cloud settings
      cloud.reverse_merge!(facet.cloud) if facet.cloud
      cloud.reverse_merge!(cluster.cloud) if cluster.cloud

      cloud.user_data({
          :chef_server            => chef_server_url,
          :validation_client_name => validation_client_name,
          #
          :node_name              => fullname,
          :organization           => organization,
          :cluster_name           => cluster_name,
          :facet_name             => facet_name,
          :facet_index            => facet_index,
          #
          :run_list               => combined_run_list,
        })
      #
      cloud.keypair(cluster_name) if cloud.keypair.nil?
      #
      self
    end

    #
    # Assembles the combined runlist.
    #
    # * run_list :first  items -- cluster then facet then server
    # * run_list :normal items -- cluster then facet then server
    # * own roles: cluster_role then facet_role
    # * run_list :last   items -- cluster then facet then server
    #
    #    Ironfan.cluster(:my_cluster) do
    #      role('f',  :last)
    #      role('c')
    #      facet(:my_facet) do
    #        role('d')
    #        role('e')
    #        role('b', :first)
    #        role('h',  :last)
    #      end
    #      role('a', :first)
    #      role('g', :last)
    #    end
    #
    # produces
    #    cluster list  [a] [c]  [cluster_role] [fg]
    #    facet list    [b] [de] [facet_role]   [h]
    #
    # yielding run_list
    #     ['a', 'b', 'c', 'd', 'e', 'cr', 'fr', 'f', 'g', 'h']
    #
    # Avoid duplicate conflicting declarations. If you say define things more
    # than once, the *earliest encountered* one wins, even if it is elsewhere
    # marked :last.
    #
    def combined_run_list
      cg = @cluster.run_list_groups
      fg = @facet.run_list_groups
      sg = self.run_list_groups
      [ cg[:first],  fg[:first],  sg[:first],
        cg[:normal], fg[:normal], sg[:normal],
        cg[:own],    fg[:own],
        cg[:last],   fg[:last],   sg[:last], ].flatten.compact.uniq
    end

    #
    # Find a Server by cluster_name, facet_name, facet_index
    #
    def self.get(cluster_name, facet_name, facet_index)
      cluster = Ironfan.load_cluster(cluster_name)
      had_facet = cluster.has_facet?(facet_name)
      facet = cluster.facet(facet_name)
      facet.bogosity true unless had_facet
      had_server = facet.has_server?( facet_index )
      server = facet.server(facet_index)
      server.bogosity :not_defined_in_facet unless had_server
      return server
    end

    #
    # Find a Server by full name
    #
    def self.get_by_name(node_name)
      ( cluster_name, facet_name, facet_index ) = node_name.split(/-/)
      self.get(cluster_name, facet_name, facet_index)
    end

    def self.all
      @@all
    end

    #
    # Actions methods which should be overridden in subclass if needed
    #

    def sync_to_cloud
      ## Not an essential step, currently; can be a no-op
      # raise_not_implemented
    end

    def sync_to_chef
      step "Syncing to chef server"
      sync_chef_node
      true
    end

    # Create a VM in the cloud if it does not already exist
    def create_server
      raise_not_implemented
    end

    # ugh. non-dry below.

    def announce_as_started
      return unless chef_node
      announce_state('start')
      chef_node.save
    end

    def announce_as_stopped
      return unless chef_node
      announce_state('stop')
      chef_node.save
    end

  protected

    def give_me_a_hostname_from_one_of_these_seven_ways_you_assholes
      # note: there are not actually seven ways. That is the least absurd part of this situation.
      case
      when cloud.public_ip
        cloud.public_ip
      when fog_server && fog_server.respond_to?(:public_ip_address) && fog_server.public_ip_address.present?
        fog_server.public_ip_address
      when fog_server && fog_server.respond_to?(:ipaddress) && fog_server.ipaddress.present?
        fog_server.ipaddress
      when fog_server && fog_server.respond_to?(:dns_name) && fog_server.dns_name.present?
        fog_server.dns_name
      when fog_server && fog_server.respond_to?(:private_ip_address) && fog_server.private_ip_address.present?
        fog_server.private_ip_address
      else
        nil
      end
    end

  end
end
