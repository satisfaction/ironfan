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
=begin
      @@DB.create_table :clusters do
        # basic fields
        primary_key :id
        String :name
        Interger :instance_num

        # action progress
        Bool :finished
        Integer :progress
        # action result
        Bool :succeed
        String :status
        # action summary
        Integer :total
        Integer :success
        Integer :failure
        Integer :running
        # error
        Integer :error_code
        String :error_msg
      end

      @@DB.create_table :facets do
        primary_key :id
        String :name
        Interger :instance_num
      end

      @@DB.create_table :servers do
        # basic fields
        primary_key :id
        String :name
        String :hostname
        String :ip_address
        String :status
        # action progress
        Bool :finished
        Integer :progress
        String :action_name
        String :action_status
        # action result
        Bool :created
        Bool :bootstrapped
        Bool :deleted
        # error
        Integer :error_code
        String :error_msg
      end
=end
    end
  end
end


