require "rdkafka"

module Events
  class KafkaProducer
    def self.from_env
      brokers = ENV.fetch("KAFKA_BROKERS")
      config = {
        "bootstrap.servers": brokers,
        "client.id": ENV.fetch("KAFKA_CLIENT_ID", "indus-platform-api"),
        "enable.idempotence": true,
        "acks": "all",
        "message.timeout.ms": ENV.fetch("KAFKA_MESSAGE_TIMEOUT_MS", "10000")
      }
      config["security.protocol"] = ENV.fetch("KAFKA_SECURITY_PROTOCOL") if ENV["KAFKA_SECURITY_PROTOCOL"].present?
      new(producer: Rdkafka::Config.new(config).producer)
    end

    def initialize(producer:)
      @producer = producer
    end

    def publish(topic:, key:, payload:, headers: {})
      handle = @producer.produce(topic: topic, key: key.to_s, payload: JSON.generate(payload), headers: headers)
      handle.wait(max_wait_timeout: 15)
    end

    def close
      @producer.close
    end
  end
end
