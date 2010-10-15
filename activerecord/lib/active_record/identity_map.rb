require "active_support/weak_hash"

module ActiveRecord
  # = Active Record Identity Map
  #
  # Ensures that each object gets loaded only once by keeping every loaded
  # object in a map. Looks up objects using the map when referring to them.
  #
  # More information on Identity Map pattern:
  #   http://www.martinfowler.com/eaaCatalog/identityMap.html
  #
  # == Configuration
  #
  # In order to disable IdentityMap, set <tt>config.active_record.identity_map = false</tt>
  # in your <tt>config/application.rb</tt> file.
  #
  # IdentityMap is enabled by default.
  #
  module IdentityMap
    extend ActiveSupport::Concern

    class << self
      attr_accessor :enabled

      def repository
        Thread.current[:identity_map] ||= Hash.new { |h,k| h[k] = ActiveSupport::WeakHash.new }
      end

      def with_repository(name = :default)
        yield if block_given?
      end

      def without
        old, self.enabled = self.enabled, false

        yield if block_given?
      ensure
        self.enabled = old
      end

      def get(klass, primary_key)
        if obj = repository[klass.symbolized_base_class][primary_key]
          return obj if obj.id == primary_key && klass == obj.class
        end

        nil
      end

      def add(record)
        repository[record.class.symbolized_base_class][record.id] = record
      end

      def remove(record)
        repository[record.class.symbolized_base_class].delete(record.id)
      end

      def clear
        repository.clear
      end

      alias enabled? enabled
      alias identity_map= enabled=
    end

    self.enabled = true

    module InstanceMethods
      # Reinitialize an Identity Map model object from +coder+.
      # +coder+ must contain the attributes necessary for initializing an empty
      # model object.
      def reinit_with(coder)
        @attributes_cache = {}
        dirty = @changed_attributes.keys
        @attributes.update(coder['attributes'].except(*dirty))
        @changed_attributes.update(coder['attributes'].slice(*dirty))
        @changed_attributes.delete_if{|k,v| v.eql? @attributes[k]}

        _run_find_callbacks

        self
      end
    end

    module ClassMethods
      def identity_map
        ActiveRecord::IdentityMap
      end
    end

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      ensure
        ActiveRecord::IdentityMap.clear
      end
    end
  end
end