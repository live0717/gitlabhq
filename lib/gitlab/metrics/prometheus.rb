require 'prometheus/client'

module Gitlab
  module Metrics
    module Prometheus
      extend ActiveSupport::Concern

      REGISTRY_MUTEX = Mutex.new
      PROVIDER_MUTEX = Mutex.new

      class_methods do
        include Gitlab::CurrentSettings
        include Gitlab::Utils::StrongMemoize

        def metrics_folder_present?
          multiprocess_files_dir = ::Prometheus::Client.configuration.multiprocess_files_dir

          multiprocess_files_dir &&
            ::Dir.exist?(multiprocess_files_dir) &&
            ::File.writable?(multiprocess_files_dir)
        end

        def prometheus_metrics_enabled?
          strong_memoize(:prometheus_metrics_enabled) do
            prometheus_metrics_enabled_unmemoized
          end
        end

        def registry
          strong_memoize(:registry) do
            REGISTRY_MUTEX.synchronize do
              strong_memoize(:registry) do
                ::Prometheus::Client.registry
              end
            end
          end
        end

        def counter(name, docstring, base_labels = {})
          safe_provide_metric(:counter, name, docstring, base_labels)
        end

        def summary(name, docstring, base_labels = {})
          safe_provide_metric(:summary, name, docstring, base_labels)
        end

        def gauge(name, docstring, base_labels = {}, multiprocess_mode = :all)
          safe_provide_metric(:gauge, name, docstring, base_labels, multiprocess_mode)
        end

        def histogram(name, docstring, base_labels = {}, buckets = ::Prometheus::Client::Histogram::DEFAULT_BUCKETS)
          safe_provide_metric(:histogram, name, docstring, base_labels, buckets)
        end

        private

        def safe_provide_metric(method, name, *args)
          metric = provide_metric(name)
          return metric if metric

          PROVIDER_MUTEX.synchronize do
            provide_metric(name) || registry.method(method).call(name, *args)
          end
        end

        def provide_metric(name)
          if prometheus_metrics_enabled?
            registry.get(name)
          else
            NullMetric.instance
          end
        end

        def prometheus_metrics_enabled_unmemoized
          metrics_folder_present? && current_application_settings[:prometheus_metrics_enabled] || false
        end
      end
    end
  end
end
