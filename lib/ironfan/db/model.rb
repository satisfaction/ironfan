module Ironfan
  module Database
    Sequel::Model.plugin(:schema)

    class Cluster < Sequel::Model
      one_to_many :facets
      one_to_many :servers

      set_schema do
        # basic fields
        primary_key :id
        String :name, :unique => true, :null => false
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

      create_table if !table_exists?

      def as_hash
        h = values.dup
        h.delete(:id)
        h
      end
    end


    class Facet < Sequel::Model
      many_to_one :cluster
      one_to_many :servers

      set_schema do
        primary_key :id
        Integer :cluster_id
        String :name
        #Integer :instance_num
      end

      create_table if !table_exists?

      def as_hash
        h = values.dup
        h.delete(:id)
        h.delete(:cluster_id)
        h
      end
    end

    class Server < Sequel::Model
      many_to_one :facet
      many_to_one :cluster

      set_schema do
        # basic fields
        primary_key :id
        Integer :facet_id
        Integer :cluster_id
        String :name, :unique => true
        String :hostname
        String :ip_address
        String :status
        # action progress
        Bool :finished
        Bool :succeed
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
            
      create_table if !table_exists?

      def as_hash
        h = values.dup
        h.delete(:id)
        h.delete(:facet_id)
        h
      end
    end
  end
end