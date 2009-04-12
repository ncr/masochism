require 'test/unit'
require 'active_support'
require 'active_support/test_case'
require 'active_record'
require 'active_reload/connection_proxy'

RAILS_ENV = 'test'

module Rails
  def self.env() RAILS_ENV end
end

class MasochismTestCase < ActiveSupport::TestCase
  setup do
    ActiveRecord::Base.configurations = default_configuration
    ActiveRecord::Base.establish_connection
  end
  
  def self.default_configuration
    { Rails.env => {'adapter' => 'sqlite3', 'database' => ':memory:'} }
  end
  
  def config
    ActiveRecord::Base.configurations
  end
  
  def enable_masochism
    ActiveReload::ConnectionProxy.setup!
  end
  
  def master
    ActiveRecord::Base.connection.master
  end
  
  def slave
    ActiveRecord::Base.connection.slave
  end
end

class ConnectionProxyTest < MasochismTestCase
  setup do
    ActiveRecord::Base.establish_connection
  end
  
  teardown do
    [ActiveRecord::Base, ActiveReload::MasterDatabase, ActiveReload::SlaveDatabase].each do |klass|
      klass.remove_connection
    end
  end
  
  def create_table
    master.create_table(:foo) {|t|}
  end
  
  def test_slave_defined_returns_false_when_slave_not_defined
    assert !ActiveReload::ConnectionProxy.slave_defined?, 'Slave should not be defined'
  end

  def test_slave_defined_returns_true_when_slave_defined
    config.update('slave_database' => {})
    assert ActiveReload::ConnectionProxy.slave_defined?, 'Slave should be defined'
  end

  def test_default
    enable_masochism
    create_table
    
    assert_equal ['foo'], slave.tables, 'Master and Slave should be the same database'
  end

  def test_master_database_outside_environment
    config.update('master_database' => config[Rails.env].dup)
    enable_masochism
    create_table

    assert_equal [], slave.tables, 'Master and Slave should be different databases'
  end

  def test_master_database_within_environment
    config[Rails.env].update('master_database' => config[Rails.env].dup)
    enable_masochism
    create_table

    assert_equal [], slave.tables, 'Master and Slave should be different databases'
  end

  def test_slave_database_within_environment
    config[Rails.env].update('slave_database' => config[Rails.env].dup)
    enable_masochism
    create_table

    assert_equal [], slave.tables, 'Master and Slave should be different databases'
  end
end
