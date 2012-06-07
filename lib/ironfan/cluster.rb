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
  # A cluster has many facets. Any setting applied here is merged with the facet
  # at resolve time; if the facet explicitly sets any attributes they will win out.
  #
  class Cluster < Ironfan::ComputeBuilder
    attr_reader :facets, :undefined_servers, :provider
    has_keys :hadoop_distro

    def initialize(provider, name, attrs={})
      super(name.to_sym, attrs)
      @provider          = provider.to_sym
      @cluster           = self
      @facets            = Mash.new
      @chef_roles        = []
      environment          :_default if environment.blank?
      create_cluster_role
    end

    def cluster
      self
    end

    def cluster_name
      name.to_s
    end

    # The auto-generated role for this cluster.
    # Instance-evals the given block in the context of that role
    #
    # @example
    #   cluster_role do
    #     override_attributes({
    #       :time_machine => { :transition_speed => 88 },
    #     })
    #   end
    #
    # @return [Chef::Role] The auto-generated role for this facet.
    def cluster_role(&block)
      @cluster_role.instance_eval( &block ) if block_given?
      @cluster_role
    end

    #
    # Retrieve or define the given facet
    #
    # @param [String] facet_name -- name of the desired facet
    # @param [Hash] attrs -- attributes to configure on the object
    # @yield a block to execute in the context of the object
    #
    # @return [Ironfan::Facet]
    #
    def facet(facet_name, attrs={}, &block)
      facet_name = facet_name.to_sym
      @facets[facet_name] ||= new_facet(self, facet_name, attrs)
      @facets[facet_name].configure(attrs, &block)
      @facets[facet_name]
    end

    def has_facet? facet_name
      @facets.include?(facet_name)
    end

    def find_facet(facet_name)
      @facets[facet_name] or raise("Facet '#{facet_name}' is not defined in cluster '#{cluster_name}'")
    end

    # All servers in this facet, sorted by facet name and index
    #
    # @return [Ironfan::ServerSlice] slice containing all servers
    def servers
      svrs = @facets.map{ |name, facet| facet.servers.to_a }
      Ironfan::ServerSlice.new(self, svrs.flatten)
    end

    #
    # A slice of a cluster:
    #
    # If +facet_name+ is nil, returns all servers.
    # Otherwise, takes slice (given by +*args+) from the requested facet.
    #
    # @param [String] facet_name -- facet to slice (or nil for all in cluster)
    # @param [Array, String] slice_indexes -- servers in that facet (or nil for all in facet).
    #   You must specify a facet if you use slice_indexes.
    #
    # @return [Ironfan::ServerSlice] the requested slice
    def slice facet_name=nil, slice_indexes=nil
      return servers if facet_name.nil?
      find_facet(facet_name).slice(slice_indexes)
    end

    def to_s
      "#{super[0..-3]} @facets=>#{@facets.keys.inspect}}>"
    end

    #
    # Resolve:
    #
    def resolve!
      facets.values.each(&:resolve!)
    end

    #
    # Render cluster meta info as a String.
    #
    # @return [String] the cluster meta info as a String.
    #
    def render()
      @@CLUSTER_TEMPLATE ||= %q{
Ironfan.cluster <%= @cluster.provider.inspect %>, <%= @cluster.name.to_s.inspect %> do

  hadoop_distro <%= @cluster.hadoop_distro.inspect %>

  cloud <%= @cloud.name.inspect %> do
    image_name <%= @cloud.image_name.inspect %>
    flavor <%= @cloud.flavor.inspect %>
  end

  <% @facets.each do |name, facet| %>
  facet <%= facet.name.inspect %> do
    instances <%= facet.instances.inspect %>
    <% facet.run_list.each { |item| %>
    <%= item.sub('[', ' "').sub(']', '"') %><% } %>
  end
  <% end %>

  cluster_role.override_attributes({
    :hadoop => {
      :distro_name => <%= @cluster.hadoop_distro.inspect %>
    }
  })
end
}
      ERB.new(@@CLUSTER_TEMPLATE).result(binding)
    end

    #
    # Save cluster meta info into the cluster definition file.
    #
    # @param [String] filename -- the full path of the file into which to save cluster meta info.
    #
    # @return [Ironfan::Cluster] the cluster.
    #
    def save(filename = nil)
      filename ||= File.join(Ironfan.cluster_path.first, "#{cluster_name}.rb")
      Chef::Log.debug("Writing cluster meta info into #{filename}")
      File.open(filename, 'w').write(render)

      self
    end

  protected

    # Creates a chef role named for the cluster
    def create_cluster_role
      @cluster_role_name = "#{name}_cluster"
      @cluster_role      = new_chef_role(@cluster_role_name, cluster)
      role(@cluster_role_name, :own)
    end

  end
end
