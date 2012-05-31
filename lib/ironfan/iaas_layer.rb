module Ironfan
  class IaasProvider
    attr_reader :servers
    attr_reader :connection_desc

    def self.init(description)
      @@connection_desc = description
    end

    def initialize
      @connection_desc = @@connection_desc

      @servers = Servers.new(self)

      Serengeti::CloudManager::Manager.set_log_level(Chef::Log.level)
    end

    def create_cluster
      Serengeti::CloudManager::Manager.create_cluster(@connection_desc, :wait => false)
    end

    def delete_cluster
      Serengeti::CloudManager::Manager.delete_cluster(@connection_desc, :wait => false)
    end

    def stop_cluster
      Serengeti::CloudManager::Manager.stop_cluster(@connection_desc, :wait => false)
    end

    def start_cluster
      Serengeti::CloudManager::Manager.start_cluster(@connection_desc, :wait => false)
    end
  end

  class IaasCollection
    
  end

  class Servers < IaasCollection
    def initialize(provider)
      @provider = provider
    end

    def all
      Serengeti::CloudManager::Manager.list_vms_cluster(@provider.connection_desc)
    end
  end
end

require File.expand_path('../../../cloud-manager/spec/config', File.dirname(__FILE__))
require 'cloud_manager'
require File.expand_path('../../../cloud-manager/spec/fog_dummy', File.dirname(__FILE__))
