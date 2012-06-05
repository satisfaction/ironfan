require 'ironfan/monitor'

module Ironfan
  module Vsphere
    class ServerSlice < Ironfan::ServerSlice
      include Ironfan::Monitor

      #
      # Override VM actions methods defined in base class
      #

      def start(bootstrap = false)
        start_monitor_progess(cluster_name)
        task = cloud.fog_connection.start_cluster
        while !task.finished?
          sleep(monitor_interval)
          monitor_start_progress(cluster_name, task.get_progress, !bootstrap)
        end
        monitor_start_progress(cluster_name, task.get_progress, !bootstrap)
        update_fog_servers(task.get_progress.result.servers)

        return task.get_result.succeed?
      end

      def stop
        start_monitor_progess(cluster_name)
        task = cloud.fog_connection.stop_cluster
        while !task.finished?
          sleep(monitor_interval)
          monitor_stop_progress(cluster_name, task.get_progress)
        end
        monitor_stop_progress(cluster_name, task.get_progress)
        update_fog_servers(task.get_progress.result.servers)

        return task.get_result.succeed?
      end

      def destroy
        start_monitor_progess(cluster_name)
        task = cloud.fog_connection.delete_cluster
        while !task.finished?
          sleep(monitor_interval)
          monitor_delete_progress(cluster_name, task.get_progress)
        end
        monitor_delete_progress(cluster_name, task.get_progress)
        update_fog_servers(task.get_progress.result.servers)

        return task.get_result.succeed?
      end

      def create_servers(threaded = true)
        start_monitor_progess(cluster_name)
        task = cloud.fog_connection.create_cluster
        while !task.finished?
          sleep(monitor_interval)
          Chef::Log.debug("Reporting progress of creating cluster VMs: #{task.get_progress.inspect}")
          monitor_launch_progress(cluster_name, task.get_progress)
        end
        Chef::Log.debug("Result of creating cluster VMs: #{task.get_progress.inspect}")
        update_fog_servers(task.get_progress.result.servers)

        Chef::Log.debug("Reporting final status of creating cluster VMs")
        monitor_launch_progress(cluster_name, task.get_progress)

        return task.get_result.succeed?
      end

      protected

      # Update fog_servers of this ServerSlice with fog_servers returned by CloudManager
      def update_fog_servers(fog_servers)
        fog_servers.each do |fog_server|
          server = self.servers.find { |svr| svr.fullname == fog_server.name }
          server.fog_server = fog_server if server
        end
      end
    end
  end
end