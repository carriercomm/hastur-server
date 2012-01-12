#
# The HasturLoggingProcessor will register a service with Hastur.
#

require "#{File.dirname(__FILE__)}/message_processor"

class HasturLoggingProcessor < HasturMessageProcessor
  
  LOG="log"
  
  def initialize
    super( LOG )
  end

  #
  # Checks if the message is a REGISTER_SERVICE type and processes if true
  #
  def process_message(msg)
    if msg["method"] == @method
      STDOUT.puts "Received a #{@method} request => #{msg}"
      # TODO(viet): place this message on STOMP

      flush_to_hastur(msg)
      return true
    end
    return false
  end
end
