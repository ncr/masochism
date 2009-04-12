module ActiveReload
  class MasterDatabase < ActiveRecord::Base
    self.abstract_class = true
  end

  class SlaveDatabase < ActiveRecord::Base
    self.abstract_class = true
  end
  
  # replaces the object at ActiveRecord::Base.connection to route read queries
  # to slave and writes to master database
  class ConnectionProxy
    def initialize(master_class, slave_class)
      @master  = master_class
      @slave   = slave_class
      @current = :slave
    end

    def master
      @master.retrieve_connection
    end

    def slave
      @slave.retrieve_connection
    end

    def current
      send @current
    end

    def self.setup!
      if slave_defined?
        setup_for ActiveReload::MasterDatabase, ActiveReload::SlaveDatabase
      else
        setup_for ActiveReload::MasterDatabase
      end
    end

    def self.slave_defined?
      !!configuration_for(:slave)
    end
    
    def self.configuration_for(type)
      config, key = ActiveRecord::Base.configurations, "#{type}_database"
      config[Rails.env][key] || config[key]
    end

    def self.setup_for(master, slave = nil)
      slave ||= ActiveRecord::Base
      slave.__send__(:include, ActiveRecordConnectionMethods)
      ActiveRecord::Observer.__send__(:include, ActiveReload::ObserverExtensions)
      
      # wire up MasterDatabase and SlaveDatabase
      establish_connections
      slave.connection_proxy = new(master, slave)
    end
    
    def self.establish_connections
      [:master, :slave].each { |type| establish_connection_for(type) }
    end
    
    def self.establish_connection_for(type)
      if connection_spec = configuration_for(type)
        klass = ActiveReload::const_get("#{type}_database".camelize)
        klass.establish_connection(connection_spec)
      end
    end

    def with_master(to_slave = true)
      set_to_master!
      yield
    ensure
      set_to_slave! if to_slave
    end

    def set_to_master!
      unless @current == :master
        @slave.logger.info "Switching to Master"
        @current = :master
      end
    end

    def set_to_slave!
      unless @current == :slave
        @master.logger.info "Switching to Slave"
        @current = :slave
      end
    end
    
    delegate :execute, :insert, :update, :delete,
      :add_column, :add_index, :add_timestamps, :assume_migrated_upto_version, :change_column,
      :change_column_default, :change_column_null, :change_table, :create_database, :create_table,
      :disable_referential_integrity, :drop_database, :drop_table, :initialize_schema_migrations_table,
      :insert_fixture, :recreate_database, :remove_column, :remove_columns, :remove_index,
      :remove_timestamps, :rename_column, :rename_table, :reset_sequence!,
      :to => :master

    def transaction(start_db_transaction = true, &block)
      with_master(start_db_transaction) do
        master.transaction(start_db_transaction, &block)
      end
    end

    def method_missing(method, *args, &block)
      current.send(method, *args, &block)
    end
    
    def respond_to?(method)
      super or current.respond_to?(method)
    end
    
    def methods
      super | current.methods
    end
  end

  module ActiveRecordConnectionMethods
    def self.included(base)
      base.alias_method_chain :reload, :master

      class << base
        def connection_proxy=(proxy)
          @@connection_proxy = proxy
        end

        # hijack the original method
        def connection
          @@connection_proxy
        end
      end
    end

    def reload_with_master(*args, &block)
      if connection.class.name == "ActiveReload::ConnectionProxy"
        connection.with_master { reload_without_master }
      else
        reload_without_master
      end
    end
  end

  # extend observer to always use the master database
  # observers only get triggered on writes, so shouldn't be a performance hit
  # removes a race condition if you are using conditionals in the observer
  module ObserverExtensions
    def self.included(base)
      base.alias_method_chain :update, :masterdb
    end

    # Send observed_method(object) if the method exists.
    def update_with_masterdb(observed_method, object) #:nodoc:
      if object.respond_to?(:connection) && object.connection.respond_to?(:with_master)
        object.class.connection.with_master do
          update_without_masterdb(observed_method, object)
        end
      else
        update_without_masterdb(observed_method, object)
      end
    end
  end
end
