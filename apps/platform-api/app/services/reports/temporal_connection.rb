require "temporalio/client"

module Reports
  class TemporalConnection
    def self.connect
      mode = ENV.fetch("TEMPORAL_AUTH_MODE", "local")
      case mode
      when "api_key"
        address = required("TEMPORAL_ADDRESS")
        namespace = required("TEMPORAL_NAMESPACE")
        key = required("TEMPORAL_API_KEY")
        Temporalio::Client.connect(address, namespace, api_key: key, tls: true)
      when "local"
        address = ENV.fetch("TEMPORAL_ADDRESS", "temporal:7233")
        if address.include?("tmprl.cloud") || !ENV.fetch("TEMPORAL_API_KEY", "").strip.empty?
          raise ArgumentError, "Temporal Cloud credentials require TEMPORAL_AUTH_MODE=api_key"
        end
        Temporalio::Client.connect(address, ENV.fetch("TEMPORAL_NAMESPACE", "default"))
      else
        raise ArgumentError, "TEMPORAL_AUTH_MODE must be local or api_key"
      end
    end

    def self.required(name)
      value = ENV.fetch(name, "").strip
      raise ArgumentError, "#{name} is required for Temporal API-key authentication" if value.empty?
      value
    end
    private_class_method :required
  end
end
