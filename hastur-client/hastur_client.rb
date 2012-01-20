#
# Starts a daemon that will monitor a machine. Statistics will be gathered
# by statsD and application plugins that will report numbers.
#
require "rubygems"
require "uuid"

# hastur libs
require "lib/json_builder"
require "lib/client_ports"
require "lib/hastur_heartbeats"
require "lib/hastur_logger"
require "lib/hastur_notification_queue"
require "lib/hastur_uuid_utils"

# receivers
require "receivers/hastur_message_receiver"

# hastur listeners
require "listeners/hastur_listener"

class HasturClient
  attr_accessor :listeners, :uuid

  def initialize
    @listeners = []
  end

  #
  # Prepares all of the listeners, queues, etc. necessary to bring the client up to life.
  #
  def start
    register_client
    start_notification_queue
    start_receiver
    start_listeners
    start_heartbeat
  end

  #
  # Message via MQ to register this machine with hastur
  #
  def register_client
    @uuid = Hastur::Client::UuidUtils.instance.get_uuid
    register_client_req = HasturJsonBuilder.get_register_client( uuid )
    # prepare the messenger with our uuid so he knows what to tag messages as
    HasturMessenger.instance.set_uuid( uuid )
    # let Hastur know that the client is alive
    HasturMessenger.instance.send(register_client_req)
    HasturLogger.instance.log("Attempting to start up the client with uuid #{uuid}")
  end

  #
  # Starts the HasturNotificationQueue which will manage and do retries on unacknowledged notifications
  #
  def start_notification_queue
    # start to monitor any outstanding notifications
    HasturNotificationQueue.instance.run
  end

  #
  # Starts the HasturMessageReceiver which will listen for messages coming from Hastur
  #
  def start_receiver
    # listen on MQ for messages from Hastur
    receiver = HasturMessageReceiver.new(HasturMessenger.instance.socket)
    receiver.start
  end

  #
  # Starts listeners which listen to localhost ports through UDP
  #
  def start_listeners
    # listen for hastur traffic on a port
    @listeners << HasturListener.new(HasturClientConfig::HASTUR_PORT, :udp)
    HasturLogger.instance.log("Listening on #{HasturClientConfig::HASTUR_PORT} for traffic")
  end

  #
  # Starts the heartbeat for this client. Sends Hastur messages every so often to let it know client is up and running
  #
  def start_heartbeat
    # periodically give a client heartbeat
    HasturHeartbeat.start( 30 )   # 30 second heartbeats
  end
end

