resource "aiven_kafka" "kafka" {
  project      = var.project
  cloud_name   = var.cloud
  service_name = var.kafka_service_name
  plan         = var.kafka_plan
}

resource "aiven_pg" "pg" {
  project      = var.project
  cloud_name   = var.cloud
  service_name = var.pg_service_name
  plan         = var.pg_plan
}

resource "aiven_opensearch" "opensearch" {
  project      = var.project
  cloud_name   = var.cloud
  service_name = var.opensearch_service_name
  plan         = var.opensearch_plan
}

resource "aiven_kafka_topic" "clickstream" {
  project      = var.project
  service_name = aiven_kafka.kafka.service_name
  topic_name   = var.topic_name
  partitions   = var.topic_partitions
  replication  = 2

  config {
    retention_ms   = var.topic_retention_ms
    cleanup_policy = "delete"
  }
}

