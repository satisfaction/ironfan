module Ironfan
  module Monitor
    def initialize_database
      require 'ironfan/db/base'
      Ironfan::Database.connect
    end

    # Monitor the progress of cluster creation
    def monitor_launch_progress(cluster_name, progress)
      initialize_database

      # update cluster progress
      cluster = Ironfan::Database::Cluster.find(:name => cluster_name)
      cluster ||= Ironfan::Database::Cluster.create(:name => cluster_name)
      cluster.finished = false # progress.finished
      cluster.progress = progress.progress / 2
      cluster.status = progress.status
      cluster.succeed = progress.result.succeed
      cluster.instance_num = progress.result.total
      cluster.total = progress.result.total
      cluster.success = progress.result.success
      cluster.failure = progress.result.failure
      cluster.running = progress.result.running
      cluster.save

      return if progress.result.servers.empty?
      # update servers progress within this cluster
      progress.result.servers.each do |vm|
        facet = Ironfan::Database::Facet.find(:name => vm.group_name, :cluster_id => cluster.id)
        facet ||= Ironfan::Database::Facet.create(:name => vm.group_name, :cluster_id => cluster.id)

        server = Ironfan::Database::Server.find(:name => vm.name)
        server ||= Ironfan::Database::Server.new
        server.name = vm.name
        server.facet_id ||= facet.id
        server.cluster_id ||= facet.cluster_id

        server.status = vm.status
        server.ip_address = vm.ip_address
        server.hostname = vm.hostname

        server.finished = false
        server.progress = 0
        server.succeed = false

        server.action_name = 'Create'
        server.action_status = vm.status

        server.created = vm.created
        server.bootstrapped = false
        server.deleted = false

        server.error_code = vm.error_code
        server.error_msg = vm.error_msg

        server.save
      end

      report_progress(cluster_name)
    end

    def start_monitor_bootstrap(cluster_name)
      Chef::Log.debug("Initailize monitoring of bootstrap progress of cluster #{cluster_name}")

      initialize_database

      cluster = Ironfan::Database::Cluster.find(:name => cluster_name)
      cluster ||= Ironfan::Database::Cluster.create(:name => cluster_name)
      cluster.finished = false # progress.finished
      cluster.progress = 50
      cluster.status = 'Bootstrapping'
      cluster.succeed = false
      cluster.success = 0
      cluster.failure = 0
      cluster.running = cluster.total
      cluster.save

      Ironfan::Database.connect[:servers].filter(:cluster_id => cluster.id).update(:bootstrapped => false)
    end

    def monitor_bootstrap_progress(svr, exit_code)
      cluster_name = svr.cluster_name.to_s
      Chef::Log.debug("Monitoring bootstrap progress of cluster #{cluster_name} with data: #{[exit_code, svr]}")
      initialize_database

      cluster = Ironfan::Database::Cluster.find(:name => cluster_name)
      server = Ironfan::Database::Server.find(:name => svr.fullname)
      if exit_code == 0 || exit_code.nil?
        server.finished = true
        server.bootstrapped = true
        server.succeed = true
        server.action_name = 'Bootstrap'
        server.action_status = 'Succeed'
        server.save

        cluster.success += 1
      else
        server.finished = true
        server.bootstrapped = false
        server.succeed = false
        server.action_name = 'Bootstrap'
        server.action_status = 'Failed'
        server.save

        cluster.failure += 1
      end

      cluster.running -= 1
      cluster.progress = (50 + (cluster.success + cluster.failure) * 50.0 / cluster.total).to_i
      cluster.finished = (cluster.running == 0)
      cluster.succeed = (cluster.success == cluster.total)
      cluster.save

      report_progress(cluster_name)
    end

    # report cluster provision progress to MessageQueue
    def report_progress(cluster_name)
      Chef::Log.debug("Begin reporting status of cluster #{cluster_name}")

      initialize_database

      # generate data in JSON format
      cluster = Ironfan::Database::Cluster.find(:name => cluster_name)
      Chef::Log.debug('Cluster: ' + cluster.inspect)

      data = cluster.as_hash
      data[:cluster_data] = {}
      data[:cluster_data][:groups] = []
      Chef::Log.debug('Facets: ' + cluster.facets.inspect)
      cluster.facets.each do |facet|
        fh = facet.as_hash
        fh[:instances] = []
        Chef::Log.debug('Servers ' + facet.servers.inspect)
        facet.servers.sort_by{ |svr| svr.name }.each do |server|
          fh[:instances] << server.as_hash
        end
        data[:cluster_data][:groups] << fh
      end

      data = JSON.parse(data.to_json) # convert keys from symbol to string
      groups = data['cluster_data']['groups']
      cluster_meta = JSON.parse(File.read(config[:from_file]))['cluster_definition']
      cluster_meta['groups'].each do |meta_group|
        groups.each do |group|
          if meta_group['name'] == group['name']
            meta_group['instances'] = group['instances']
            break
          end
        end
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
  end
end