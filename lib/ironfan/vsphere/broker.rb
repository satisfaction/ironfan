require 'ironfan/vsphere/iaas_layer'
module Ironfan
  Script.class_eval do

    def initialize_ironfan_broker(config_file)
      initialize_iaas_provider(config_file)
      save_distro_info(config_file)
      save_message_queue_server_info(config_file)
    end

    def initialize_iaas_provider(filename)
      Ironfan::Vsphere::IaasProvider.init(JSON.parse(File.read(filename))) # initialize IaasProvider
    end

    def save_distro_info(filename)
      Chef::Log.debug("Loading hadoop distro info")
      begin
        cluster_def = JSON.parse(File.read(filename))['cluster_definition']
        distro_name = cluster_def['distro']
        distro_repo = cluster_def['distro_map']
        distro_repo['id'] = distro_name
      rescue StandardError => e
        raise e, "Malformed hadoop distro info in cluster definition file."
      end

      Chef::Log.debug("Saving hadoop distro info to Chef Data Bag: #{distro_repo}")
      data_bag_name = "hadoop_distros"
      databag = Chef::DataBag.load(data_bag_name) rescue databag = nil
      if databag.nil?
        databag = Chef::DataBag.new
        databag.name(data_bag_name)
        databag.save
      end
      databag_item = Chef::DataBagItem.load(distro_name) rescue databag_item = nil
      databag_item ||= Chef::DataBagItem.new
      databag_item.data_bag(data_bag_name)
      databag_item.raw_data = distro_repo
      databag_item.save
    end

    def save_message_queue_server_info(filename)
      Chef::Log.debug("Loading hadoop message queue server info")
      begin
        message_queue_server_info = JSON.parse(File.read(filename))['system_properties']
        Chef::Config[:knife][:rabbitmq_host] = message_queue_server_info['rabbitmq_host']
        Chef::Config[:knife][:rabbitmq_port] = message_queue_server_info['rabbitmq_port']
        Chef::Config[:knife][:rabbitmq_username] = message_queue_server_info['rabbitmq_username']
        Chef::Config[:knife][:rabbitmq_password] = message_queue_server_info['rabbitmq_password']
        Chef::Config[:knife][:rabbitmq_exchange] = message_queue_server_info['rabbitmq_exchange']
        Chef::Config[:knife][:rabbitmq_channel] = message_queue_server_info['rabbitmq_channel']
      rescue StandardError => e
        raise e, "Malformed hadoop message queue server info in cluster definition file."
      end
    end
  end
end