module Ironfan
  module Monitor
    MONITOR_INTERVAL ||= 10

    # VM Status
    STATUS_VM_NOT_EXIST ||= 'Not Exist'
    STATUS_BOOTSTAP_SUCCEED ||= 'Service Ready'
    STATUS_BOOTSTAP_FAIL ||= 'Bootstrap Failed'

    # Actions being performed on VM
    ACTION_CREATE_VM ||= 'Creating VM'
    ACTION_BOOTSTRAP_VM ||= 'Bootstrapping VM'

    def update_fog_servers(target, fog_servers)
      Chef::Log.debug("updating Ironfan::Server.fog_server with fog_servers returned by CloudManager: #{fog_servers.inspect}")
      fog_servers.each do |fog_server|
        server_slice = target.servers.find { |svr| svr.fullname == fog_server.name }
        server_slice.servers.fog_server = fog_server if server_slice and server_slice.servers
      end
    end

    def start_monitor_launch(cluster_name)
      Chef::Log.debug("Initialize monitoring of launch progress of cluster #{cluster_name}")
      nodes = cluster_nodes(cluster_name)
      nodes.each do |node|

        attrs = get_provision_attrs(node)
        attrs[:finished] = false
        attrs[:succeed] = nil
        attrs[:progress] = 0
        attrs[:action] = ACTION_CREATE_VM
        attrs[:status] ||= STATUS_VM_NOT_EXIST
        set_provision_attrs(node, attrs)
        node.save
      end

      # report_progress(cluster_name) # Don't report because vm_name is nil
    end

    def start_monitor_bootstrap(cluster_name)
      Chef::Log.debug("Initialize monitoring of bootstrap progress of cluster #{cluster_name}")
      nodes = cluster_nodes(cluster_name)
      nodes.each do |node|
        attrs = get_provision_attrs(node)
        attrs[:finished] = false
        attrs[:succeed] = nil
        attrs[:bootstrapped] = false
        attrs[:progress] = 50
        attrs[:action] = ACTION_BOOTSTRAP_VM
        set_provision_attrs(node, attrs)
        node.save
      end

      report_progress(cluster_name)
    end

    # Monitor the progress of cluster creation
    def monitor_launch_progress(cluster_name, progress)
      Chef::Log.debug('update launch progress of servers within this cluster')
      monitor_iaas_action_progress(cluster_name, progress)
    end

    def monitor_iaas_action_progress(cluster_name, progress, is_last_action = false)
      return if progress.result.servers.empty?

      has_progress = false
      progress.result.servers.each do |vm|
        # Get VM attributes
        attrs = vm.to_hash
        # when creating VM is done, set the progress to 50%; once bootstrapping VM is done, set the progress to 100%
        attrs[:progress] = vm.get_create_progress / 2 if !is_last_action
        # reset to correct status
        if !is_last_action and attrs[:finished] and attrs[:succeed]
          attrs[:finished] = false
          attrs[:succeed] = nil
        end

        # Save progress data to ChefNode
        node = Chef::Node.load(vm.name)
        if node[:provision] and node[:provision][:progress] == attrs[:progress]
          Chef::Log.debug("skip updating server #{vm.name} since no progress")
          next
        end
        has_progress = true
        set_provision_attrs(node, attrs)
        node.save
      end

      if has_progress
        report_progress(cluster_name)
      else
        Chef::Log.debug("skip reporting cluster status since no progress")
      end
    end

    def monitor_bootstrap_progress(svr, exit_code)
      cluster_name = svr.cluster_name.to_s
      Chef::Log.debug("Monitoring bootstrap progress of cluster #{cluster_name} with data: #{[exit_code, svr]}")

      # Save progress data to ChefNode
      node = Chef::Node.load(svr.fullname)
      attrs = get_provision_attrs(node)
      if exit_code == 0
        attrs[:finished] = true
        attrs[:bootstrapped] = true
        attrs[:succeed] = true
        attrs[:status] = STATUS_BOOTSTAP_SUCCEED
      else
        attrs[:finished] = true
        attrs[:bootstrapped] = false
        attrs[:succeed] = false
        attrs[:status] = STATUS_BOOTSTAP_FAIL
      end
      attrs[:action] = ''
      attrs[:progress] = 100
      set_provision_attrs(node, attrs)
      node.save

      report_progress(cluster_name)
    end

    # report progress of deleting cluster to MessageQueue
    def monitor_delete_progress(cluster_name, progress)
      Chef::Log.debug("Begin reporting progress of deleting cluster #{cluster_name}")
      report_refined_progress(cluster_name, progress)
    end

    # report progress of stopping cluster to MessageQueue
    def monitor_stop_progress(cluster_name, progress)
      Chef::Log.debug("Begin reporting progress of stopping cluster #{cluster_name}")
      monitor_iaas_action_progress(cluster_name, progress, true)
    end

    # report progress of starting cluster to MessageQueue
    def monitor_start_progress(cluster_name, progress, is_last_action)
      Chef::Log.debug("Begin reporting progress of starting cluster #{cluster_name}")
      monitor_iaas_action_progress(cluster_name, progress, is_last_action)
    end

    # report cluster provision progress without VM detail info to MessageQueue
    def report_refined_progress(cluster_name, progress)
      cluster = Mash.new
      cluster[:progress] = progress.progress
      cluster[:finished] = progress.finished?
      cluster[:succeed] = progress.result.succeed?
      cluster[:total] = progress.result.total
      cluster[:success] = progress.result.success
      cluster[:failure] = progress.result.failure
      cluster[:running] = progress.result.running
      cluster[:cluster_data] = Mash.new
      cluster[:cluster_data][:name] = cluster_name

      data = JSON.parse(cluster.to_json)

      # send to MQ
      send_to_mq(data)
    end

    # report cluster provision progress to MessageQueue
    def report_progress(cluster_name)
      Chef::Log.debug("Begin reporting status of cluster #{cluster_name}")

      data = get_cluster_data(cluster_name)

      # merge nodes data with cluster definition
      groups = data['cluster_data']['groups']
      cluster_meta = JSON.parse(File.read(config[:from_file]))['cluster_definition']
      cluster_meta['groups'].each do |meta_group|
        meta_group['instances'] = groups[meta_group['name']]['instances']
      end
      data['cluster_data'].merge!(cluster_meta)

      # send to MQ
      send_to_mq(data)
      Chef::Log.debug('End reporting cluster status')
    end

    def send_to_mq(data)
      if (@last_data == data.to_json)
        Chef::Log.debug("Skip reporting progress since no change")
        return
      end
      @last_data = data.to_json

      Chef::Log.debug("About to send data to MessageQueue: #{data.pretty_inspect}")

      return if monitor_disabled?

      require 'bunny'

      # load MessageQueque configuration
      mq_server = Chef::Config[:knife][:mq_server] || 'localhost'
      mq_exchange_id = Chef::Config[:knife][:mq_exchange_id] || 'bddtask'
      mq_channel_id = config[:channel]

      b = Bunny.new(:host => mq_server, :logging => false)
      # start a communication session with the RabbitMQ server
      b.start

      # create/get exchange
      exch = b.exchange(mq_exchange_id, :durable => true)

      # publish message to exchange
      exch.publish(data.to_json, :key => mq_channel_id)

      # message should now be picked up by the consumer so we can stop
      b.stop
    end

    def monitor_disabled?
      if Chef::Config[:knife][:monitor_disabled]
        Chef::Log.warn('Monitoring is disabled. Will not send message to MQ.')
        return true
      else
        return false
      end
    end

    def cluster_nodes(cluster_name)
      nodes = []
      while nodes.empty?
        Chef::Search::Query.new.search(:node, "cluster_name:#{cluster_name}") do |n|
          nodes.push(n)
        end
        Chef::Log.debug("nodes in cluster #{cluster_name} returned by Chef Search are : #{nodes}")
        sleep(3)
      end
      nodes.sort_by! { |n| n.name }
    end

    # generate cluster nodes data in JSON format
    def get_cluster_data(cluster_name)
      cluster = Mash.new
      cluster[:total] = 0
      cluster[:success] = 0
      cluster[:failure] = 0
      cluster[:running] = 0
      cluster[:finished] = false
      cluster[:succeed] = nil
      cluster[:progress] = 0
      cluster[:cluster_data] = Mash.new
      groups = cluster[:cluster_data][:groups] = Mash.new
      nodes = cluster_nodes(cluster_name)
      nodes.each do |node|
        # create groups
        group = groups[node.facet_name] || Mash.new
        group[:name] ||= node.facet_name
        group[:instances] ||= []
        group[:instances] << node[:provision].to_hash
        groups[node.facet_name] = group
        # create cluster summary
        server = node[:provision]
        cluster[:success] += 1 if server[:finished] and server[:succeed]
        cluster[:failure] += 1 if server[:finished] and !server[:succeed]
        cluster[:running] += 1 if !server[:finished]
        cluster[:progress] += server[:progress]
      end
      cluster[:total] = nodes.length
      cluster[:progress] /= cluster[:total] if cluster[:total] != 0
      cluster[:finished] = (cluster[:running] == 0)
      cluster[:succeed] = (cluster[:success] == cluster[:total])

      JSON.parse(cluster.to_json) # convert keys from symbol to string
    end

    protected

    def get_provision_attrs(chef_node)
      chef_node[:provision] ? chef_node[:provision].to_hash : Hash.new
    end

    def set_provision_attrs(chef_node, attrs)
      chef_node[:provision] = attrs
    end
  end
end