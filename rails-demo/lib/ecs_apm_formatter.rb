require "json"
require "time"

# Logger formatter that emits one ECS-JSON line per record, enriched with the
# current Elastic APM trace / transaction / span ids. Kibana uses those ids to
# line each log entry up with the trace that produced it.
class EcsApmFormatter < ::Logger::Formatter
  SERVICE = ENV.fetch("ELASTIC_APM_SERVICE_NAME", "ruby-rails-error-simulator")

  def call(severity, time, progname, msg)
    doc = {
      "@timestamp"   => time.utc.iso8601(3),
      "log.level"    => severity.to_s.downcase,
      "message"      => stringify(msg),
      "ecs.version"  => "8.11.0",
      "service.name" => SERVICE,
    }
    doc["log.logger"] = progname if progname

    # `log_ids` yields the active ids (nil when there is no current transaction,
    # e.g. for boot-time log lines). Guard on running? so this is safe before the
    # agent has started.
    if defined?(ElasticAPM) && ElasticAPM.running?
      ElasticAPM.log_ids do |transaction_id, span_id, trace_id|
        doc["transaction.id"] = transaction_id if transaction_id
        doc["span.id"]        = span_id if span_id
        doc["trace.id"]       = trace_id if trace_id
      end
    end

    "#{JSON.generate(doc)}\n"
  end

  private

  def stringify(msg)
    case msg
    when String    then msg
    when Exception then "#{msg.message} (#{msg.class})"
    else msg.inspect
    end
  end
end
