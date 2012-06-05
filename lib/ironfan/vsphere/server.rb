module Ironfan
  module Vsphere
    class Server < Ironfan::Server

      def initialize(*args)
        super(*args)
      end

      #
      # Override VM attributes methods defined in base class
      #

      def running?
        has_cloud_state?('poweredOn')
      end

      def startable?
        has_cloud_state?('poweredOff')
      end

      def sync_volume_attributes
        super

        return if fog_server.nil? or fog_server.volumes.nil? or fog_server.volumes.empty?
        mount_point_to_device = {}
        device_to_disk = {}
        fog_server.volumes.each do |disk|
          # disk should equal to '/dev/sdb' or 'dev/sdc', etc.
          device = disk + '1'
          mount_point = '/mnt/' + device.split('/').last
          mount_point_to_device[mount_point] = device
          device_to_disk[device] = disk
        end
        @chef_node.normal[:disk][:data_disks]  = mount_point_to_device
        @chef_node.normal[:disk][:disk_devices] = device_to_disk
      end
    end
  end
end