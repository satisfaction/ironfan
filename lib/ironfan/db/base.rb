require 'sequel'

module Ironfan

  module Database
    @@conn_str = 'sqlite:///var/ironfan/ironfan.db'

    def self.connect(conn_str = nil)
      @@conn_str = conn_str if conn_str
      @@DB = Sequel.connect(@@conn_str)
      initialize_db
      require 'ironfan/db/model'
      @@DB
    end

    def self.initialize_db
      if File.exists?(@@conn_str.split('//')[1])
        return
      end
    end
  end
end


