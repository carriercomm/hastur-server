#
# Base class for an Hastur listener. The tcp and udp socket interactions are abstracted to this level.
# The business logic for what happens on each message is up to the subclasses to decide.
#

require "socket"
require "#{File.dirname(__FILE__)}/../msg_processors/service_processor"
require "#{File.dirname(__FILE__)}/../lib/hastur_error_processor"

class HasturListener
  attr_accessor :type, :port, :server, :current_thread, :processors

  #
  # Constructs the base listener and sets up the socket objects
  #
  def initialize(port, type)
    @port = port
    @type = type
    # automatically populate message processors by reading the msg_processors/ folder
    @processors = scan_for_msg_processors()
    # construct the socket objects to listen on the port
    setup_sockets()
    # asynchronously deal with messages
    listen_for_messages()
  end

  #
  # Scans the msg_processors/ folder for all 
  #
  def scan_for_msg_processors
    processors = []
    Dir.glob("#{File.dirname(__FILE__)}/../msg_processors/*_processor.rb").each do |f|
      require "#{f}"
      begin
        class_name = compute_class_name(f)
        STDOUT.puts "Loading message processor: #{class_name}"
        processors << eval( class_name ).new unless class_name == "HasturMessageProcessor"
      rescue Exception => e
        HasturErrorProcessor.instance.log( e.message )
      end
    end
    processors
  end

  #
  # Computes the HasturMessageProcessor subclass name from the file name
  #
  def compute_class_name(f)
    begin
      class_name = "Hastur"
      tokens = f.split("/")[-1].split(".")[0].split("_")
      tokens.each do |token|
        class_name << token.capitalize
      end
      return class_name
    rescue Exception => e
      HasturErrorProcessor.instance.log( "Unable to parse the file name #{f}" )
    end
  end

  #
  # Listen for messages in an asynchronous way
  #
  def listen_for_messages
    @current_thread = Thread.start do     # this makes the listener asynch
      if type == :tcp
        # listen for TCP clients
        loop do
          # for each client, listen to what they have to say and process each incoming message
          Thread.start(@server.accept) do |socket|
            begin
              STDOUT.puts "Accepted connection on #{@port}"
              while(msg = socket.gets)
                STDOUT.puts "tcp message recieved: #{msg}"
                process_message(msg)
              end
            rescue Exception => e
              HasturErrorProcessor.instance.log( "Error occurred with recieving packets on #{@port}: #{e.message}" )
            end
          end
        end
      elsif type == :udp
        # listen for UDP packets
        while msg = @socket.recv(65507)  # maxlength is 65507 bytes for UDP
          STDOUT.puts "udp message recieved: #{msg}"
          process_message(msg)
        end
      end
    end
  end

  #
  # A holder so that sub-classes can override. This method should be overridden by subclasses to process 
  # messages off of the listener.
  #
  def process_message(msg)
    begin
      msg = JSON.parse(msg)
      # attempt to process the msg with each available message processor
      @processors.each do |p|
        if p.process_message( msg )
          break   # stop if the processing succeeded
        end
      end
    rescue Exception => e
      HasturErrorProcessor.instance.log( "Unable to process message: #{e.message}" )
    end
  end

  #
  # Sets up the sockets to listen
  #
  def setup_sockets()
    if type == :tcp             # initialize TCP server
      @server = TCPServer.new @port
    elsif type == :udp          # initialize UDP socket
      @socket = UDPSocket.new
      @socket.bind("localhost", @port)
    else
      raise "Only supported protocols are tcp and udp. You tried #{type}."
    end
  end
end
