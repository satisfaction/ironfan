module VHelper
end

module Iaas
  class IaasProvider
    attr_reader :servers
    attr_reader :connection_desc

    def self.init(description)
      @@connection_desc = description
    end

    def initialize
      @connection_desc = @@connection_desc

      @servers = Servers.new(self)
    end
  end

  class IaasCollection
    
  end

  class Servers < IaasCollection
    def initialize(provider)
      @provider = provider
    end

    def all
      VHelper::CloudManager::Manager.list_vms_cluster(@provider.connection_desc)
    end
  end
end


require File.expand_path('../../../cloud-manager/spec/config', File.dirname(__FILE__))
require 'cloud_manager'
require File.expand_path('../../../cloud-manager/spec/fog_dummy', File.dirname(__FILE__))
