require 'jsonpath'

module Feta
  ##
  # JsonParser
  # @see Feta::Parser
  class JsonParser < Feta::Parser
    ##
    # @param record [Feta::OriginalRecord] a record whose properties can
    # be parsed by the parser instance.
    # @param root_path [String] JsonPath that identifies the root path for
    # the desired parse root.
    # @see http://goessner.net/articles/JsonPath/ JsonPath
    def initialize(record, root_path = '$')
      @root = Value.new(JsonPath.on(record.content, root_path).first)
      super(record)
    end

    ##
    # JsonParser::Value
    # @see Feta::Parser::Value
    class Value < Feta::Parser::Value
      attr_accessor :node

      def initialize(node)
        @node = node
      end

      def attributes
        raise NotImplementedError, 'Attributes are not supported for JSON'
      end

      def children
        @node.is_a?(Hash) ? @node.keys : []
      end

      def value
        @node.is_a?(Hash) ? @node.to_s : @node
      end

      def values?
        !select_values.empty?
      end

      private

      ##
      # @see Feta::Parser#get_child_nodes
      #
      # @param name_exp [String]  Object property name
      # @return [Feta::Parser::ValueArray]
      def get_child_nodes(name, node: @node)
        return get_child_nodes(name, node: node.flatten.first) if
          node.is_a?(Array)

        if node[name].is_a?(Array)
          vals = node[name].map { |node| self.class.new(node) }
        else
          vals = Array(self.class.new(node[name]))
        end

        vals.reject! { |n| n.node.nil? }
        Feta::Parser::ValueArray.new(vals)
      end

      def attribute(name)
        msg = "Attributes are not supported for JSON; got attribute `#{name}`"
        raise NotImplementedError, msg
      end

      def select_values
        @node.is_a?(Hash) ? [] : @node
      end
    end
  end
end
