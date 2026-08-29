# Capacity and scaling

Review weekly: API p95/CPU/memory, HPA desired versus available pods, node
headroom and zone balance, RDS Proxy connections, Aurora ACU/IO/storage,
ElastiCache ECPU/storage, MSK throughput/lag, Temporal queue latency, NAT and
CloudFront/WAF volume, and provider quotas. Forecast 30 and 90 days.

Maintain 50% production headroom for API, stream connections, Kafka throughput,
workflow starts, database connections, and report artifact writes. Raise quotas
and Terraform maxima before demand reaches 70%; load-test staging with the exact
production image. Scaling down requires one week below 40%, no active incident,
and verified rollback capacity. Never use Redis eviction or Kafka retention as
an emergency substitute for correctness.
