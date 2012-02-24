require 'multi_json'
require 'yajl'
require 'hastur-server/exception'

MultiJson.engine = :yajl

module Hastur
  module Input
    module JSON
      def self.decode_packet(data)
        hash = MultiJson.decode(data, :symbolize_keys => true)

        unless hash.has_key? :_route
          raise Hastur::PacketDecodingError.new "missing :_route key in JSON" 
        end

        return hash
      end

      # Returns nil on invalid/unparsable data.
      def self.decode(data)
        # do an initial test for json-ish input before calling through to the parser
        test = data.strip
        if test.start_with?('{') and test.end_with?('}')
          decode_packet(data) rescue nil
        else
          return nil
        end
      end
    end
  end
end