module Ironfan
  module Monitor
    MONITOR_INTERVAL = 10

    # Monitor the progress of cluster creation
    def monitor_launch_progress(cluster_name, progress)
      Chef::Log.debug('update launch progress of servers within this cluster')
      return if progress.result.servers.empty?
      progress.result.servers.each do |vm|
        # Save progress data to ChefNode
        node = Chef::Node.load(vm.name)
        node[:provision] ||= Mash.new
        attrs = node[:provision]

        attrs[:name] = vm.name
        attrs[:hostname] = vm.hostname
        attrs[:ip_address] = vm.ip_address
        attrs[:status] = vm.status

        attrs[:finished] = vm.ready? # FIXME should use 'vm.finished?'
        attrs[:progress] = vm.get_create_progress / 2
        attrs[:succeed] = vm.ready? # FIXME should use 'vm.succeed?'

        attrs[:action_name] = 'Create'
        attrs[:action_status] = vm.status

        attrs[:created] = vm.created
        attrs[:bootstrapped] = false
        attrs[:deleted] = false

        attrs[:error_code] = vm.error_code
        attrs[:error_msg] = vm.error_msg

        node.save
      end

      report_progress(cluster_name)
    end

    def start_monitor_launch(cluster_name)
      Chef::Log.debug("Initailize monitoring of launch progress of cluster #{cluster_name}")
      nodes = cluster_nodes(cluster_name)
      nodes.each do |node|
        node[:provision] ||= Mash.new
        attrs = node[:provision]
        attrs[:finished] = false
        attrs[:succeed] = nil
        attrs[:progress] = 0
        attrs[:action_name] = 'Create'
        attrs[:action_status] = 'Running'
        node.save
      end
    end

    def start_monitor_bootstrap(cluster_name)
      Chef::Log.debug("Initailize monitoring of bootstrap progress of cluster #{cluster_name}")
      nodes = cluster_nodes(cluster_name)
      nodes.each do |node|
        node[:provision] ||= Mash.new
        attrs = node[:provision]
        attrs[:finished] = false
        attrs[:succeed] = nil
        attrs[:bootstrapped] = false
        attrs[:progress] = 50
        attrs[:action_name] = 'Bootstrap'
        attrs[:action_status] = 'Running'
        node.save
      end

      report_progress(cluster_name)
    end

    def monitor_bootstrap_progress(svr, exit_code)
      cluster_name = svr.cluster_name.to_s
      Chef::Log.debug("Monitoring bootstrap progress of cluster #{cluster_name} with data: #{[exit_code, svr]}")

      # Save progress data to ChefNode
      node = Chef::Node.load(svr.fullname)
      node[:provision] ||= Mash.new
      attrs = node[:provision]
      if exit_code == 0 || exit_code.nil?
        attrs[:finished] = true
        attrs[:bootstrapped] = true
        attrs[:succeed] = true
        attrs[:action_name] = 'Bootstrap'
        attrs[:action_status] = 'Succeed'
      else
        attrs[:finished] = true
        attrs[:bootstrapped] = false
        attrs[:succeed] = false
        attrs[:action_name] = 'Bootstrap'
        attrs[:action_status] = 'Failed'
      end
      attrs[:progress] = 100
      node.save

      report_progress(cluster_name)
    end

    # report cluster provision progress to MessageQueue
    def report_progress(cluster_name)
      Chef::Log.debug("Begin reporting status of cluster #{cluster_name}")

      # generate cluster nodes data in JSON format
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
      Chef::Search::Query.new.search(:node, "cluster_name:#{cluster_name}") do |n|
        nodes.push(n) unless n.blank? || (n.cluster_name != cluster_name.to_s)
      end
      nodes.sort_by! { |n| n.name }
    end

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
        cluster[:success] += 1 if server[:succeed]
        cluster[:failure] += 1 if server[:finished] and !server[:succeed]
        cluster[:running] += 1 if !server[:finished]
        cluster[:progress] += server[:progress]
      end
      cluster[:total] = nodes.length
      cluster[:progress] /= cluster[:total] if cluster[:total] != 0

      JSON.parse(cluster.to_json) # convert keys from symbol to string
    end
  end
end