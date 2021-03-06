module Feta
  ##
  # Provides the public interface for defining and running metadata Mappings.
  # Define mappings by passing a block to #define with registered DSL methods;
  # in the simple case pass values to property names:
  #
  #   Feta::Mapper.define do
  #     property_name   value
  #     property_two    another_value do |val|
  #       transform_value(val)
  #     end
  #
  #     nested_resource_property :class => DPLA::MAP::Agent do
  #       agent_property  agent_value
  #     end
  #   end
  #
  # #define accepts :class as an option, to specify the model class to use.
  # The default is DPLA::MAP::Aggregation:
  #
  #   Feta::Mapper.define :class => MyModelClass {}
  #
  # Once a Mapping is defined, create mapped records with #map to return objects
  # of the specified class.
  #
  # @see Mapping
  # @see MappingDSL
  module Mapper
    module_function

    ##
    # Creates mappings and passes DSL methods through to them, then adds them to
    # a global registry.
    #
    # @param name [Symbol] a unique name for the mapper in the registry.
    # @param opts [Hash] options to pass to the mapping instance, options are:
    #   :class, :parser, and :parser_args
    # @yield A block passed through to the mapping instance containing the
    #   mapping in the language specified by MappingDSL
    def define(name, opts = {}, &block)
      klass = opts.fetch(:class, DPLA::MAP::Aggregation)
      parser = opts.fetch(:parser, Feta::JsonParser)
      parser_args = opts.fetch(:parser_args, nil)
      map = Feta::Mapping.new(klass, parser, *parser_args)
      map.instance_eval(&block) if block_given?
      Registry.register!(name, map)
    end

    ##
    # Maps OriginalRecords to the specified model class using a registered
    # Feta::Mapping.
    #
    # @param name [Symbol] the name of a registered mapper to use
    # @param records A record or list of records that respond to #to_s
    # @return [Array] An array of objects of the model class, with properties
    #   set by the mapping.
    #
    # @see Mapping
    def map(name, records)
      mapping = Registry.get(name)
      records = Array(records) unless records.is_a? Enumerable

      result = records.map do |rec|
        begin
          mapping.process_record(rec)
        rescue => e
          Rails.logger.error(e.message)
          e.message
        end
      end
    end

    ##
    # An application-wide registry of defined mappings
    Registry = Class.new(Feta::Registry)

    ##
    # A SoftwareAgent to run mapping processes.
    #
    # @example to map the records harvested by the harvest activity with ID 1:
    #   Feta::Mapper::Agent.enqueue(name: :scdl_qdc,
    #     generator_uri: 'http://ldp.local.dp.la/ldp/activity/1')
    #
    # @see: Feta::SoftwareAgent, Feta::Activity
    class Agent
      include SoftwareAgent
      include EntityConsumer

      # @!attribute [r] name
      #   @return [Symbol]
      attr_reader :name

      ##
      # @return [Symbol] the default queue for jobs using this agent
      def self.queue_name
        :mapping
      end

      ##
      # @see Feta::Activity#entities
      # @see Feta::EntityBehavior
      # @see Feta::SoftwareAgent#entity_behavior
      def entity_behavior
        @entity_behavior ||= Feta::AggregationEntityBehavior
      end

      ##
      # @param opts [Hash]
      # @option opts [#to_sym] name  the symbol naming the mapping to use
      def initialize(opts = {})
        @name = opts.fetch(:name).to_sym
        @entity_behavior = self.class.entity_behavior
        assign_generator_activity!(opts)
      end

      ##
      # @param activity_uri [RDF::URI] the uri of the activity to attribute
      #   for provenance purposes (default: nil)
      # @see SoftwareAgent#run
      def run(activity_uri = nil)
        Feta::Mapper.map(name, entities).each do |rec|
          begin
            rec.mint_id! if rec.node?
            activity_uri ? rec.save_with_provenance(activity_uri) : rec.save
          rescue => e
            Rails.logger.error("Error saving record: #{rec.try(:rdf_subject)}\n" \
                               "#{e.message}\n#{e.backtrace}")
          end
        end
      end
    end
  end
end
