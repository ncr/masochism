require 'test/unit'
require 'active_record'
require 'active_reload/connection_proxy'

RAILS_ENV = 'test'

module Rails
  def self.env() RAILS_ENV end
end

module ActiveReload
  class ConnectionProxyTest < Test::Unit::TestCase
    
    def setup
      ActiveRecord::Base.configurations = {
        Rails.env => {'adapter' => 'sqlite3', 'database' => ':memory:'}
      }
      ActiveRecord::Base.establish_connection
    end
    
    def config
      ActiveRecord::Base.configurations
    end
    
    def teardown
      [ActiveRecord::Base, ActiveReload::MasterDatabase, ActiveReload::SlaveDatabase].each do |klass|
        klass.remove_connection
      end
    end

    def test_slave_defined_returns_false_when_slave_not_defined
      assert !ActiveReload::ConnectionProxy.slave_defined?, 'Slave should not be defined'
    end

    def test_slave_defined_returns_true_when_slave_defined
      config.update('slave_database' => {})
      assert ActiveReload::ConnectionProxy.slave_defined?, 'Slave should be defined'
    end

    def test_default
      ActiveReload::ConnectionProxy.setup!

      ActiveRecord::Base.connection.master.execute('CREATE TABLE foo (id int)')
      assert_equal ['foo'], ActiveRecord::Base.connection.tables, 'Master and Slave should be the same database'
      assert_equal ['foo'], ActiveRecord::Base.connection.slave.tables, 'Master and Slave should be the same database'
    end

    def test_master_database_outside_environment
      config.update('master_database' => config[Rails.env].dup)
      ActiveReload::ConnectionProxy.setup!

      ActiveRecord::Base.connection.master.execute('CREATE TABLE foo (id int)')
      assert_equal [], ActiveRecord::Base.connection.tables, 'Master and Slave should be different databases'
      assert_equal [], ActiveRecord::Base.connection.slave.tables, 'Master and Slave should be different databases'
    end

    def test_master_database_within_environment
      config[Rails.env].update('master_database' => config[Rails.env].dup)
      ActiveReload::ConnectionProxy.setup!

      ActiveRecord::Base.connection.master.execute('CREATE TABLE foo (id int)')
      assert_equal [], ActiveRecord::Base.connection.tables, 'Master and Slave should be different databases'
      assert_equal [], ActiveRecord::Base.connection.slave.tables, 'Master and Slave should be different databases'
    end

    def test_slave_database_within_environment
      config[Rails.env].update('slave_database' => config[Rails.env].dup)
      ActiveReload::ConnectionProxy.setup!

      ActiveRecord::Base.connection.master.execute('CREATE TABLE foo (id int)')
      assert_equal [], ActiveRecord::Base.connection.tables, 'Master and Slave should be different databases'
      assert_equal [], ActiveRecord::Base.connection.slave.tables, 'Master and Slave should be different databases'
    end
  end
end
