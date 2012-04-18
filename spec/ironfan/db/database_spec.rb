require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

require IRONFAN_DIR("lib/ironfan")

describe Ironfan do
  describe 'create_tables' do
    before :all do
      @logger = Logger.new(STDOUT)
      db_file = '/var/ironfan/ironfan-test.db'
      File.delete(db_file) rescue nil
      require 'ironfan/db/base'
      @conn_str = "sqlite://#{db_file}"
      DB = Ironfan::Database.connect(@conn_str)
    end

    it 'creates the database and tables' do
      DB.should_not == nil
      DB.tables.to_s.should == "[:clusters, :facets, :servers]"
    end

    it 'inserts a row into table cluster' do
      Ironfan::Database::Cluster.insert(:name => 'cluster_test')
      cluster = Ironfan::Database::Cluster.find(:name => 'cluster_test')
      cluster.name.should == 'cluster_test'
      cluster.facets.should == []

      Ironfan::Database::Facet.insert(:name => 'master', :cluster_id => cluster.id)

      facet = Ironfan::Database::Facet.find(:name => 'master', :cluster_id => cluster.id)
      facet.name.should == 'master'

      Ironfan::Database::Server.insert(:name => 'cluster_test-master-0', :facet_id => facet.id)
      server = Ironfan::Database::Server.find(:name => 'cluster_test-master-0')
      server.name.should == 'cluster_test-master-0'

      cluster = Ironfan::Database::Cluster.find(:name => 'cluster_test')
      p cluster.facets
      p cluster.facets[0].servers
    end
  end
end