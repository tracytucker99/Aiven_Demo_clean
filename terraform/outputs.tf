output "project_name" {
  value = var.project
}

output "kafka_service_name" {
  value = aiven_kafka.kafka.service_name
}

output "pg_service_name" {
  value = aiven_pg.pg.service_name
}

output "opensearch_service_name" {
  value = aiven_opensearch.opensearch.service_name
}

output "kafka_uri" {
  value     = aiven_kafka.kafka.service_uri
  sensitive = true
}

output "pg_uri" {
  value     = aiven_pg.pg.service_uri
  sensitive = true
}

output "opensearch_uri" {
  value     = aiven_opensearch.opensearch.service_uri
  sensitive = true
}

output "kafka_username" {
  value     = aiven_kafka.kafka.service_username
  sensitive = true
}

output "kafka_password" {
  value     = aiven_kafka.kafka.service_password
  sensitive = true
}

output "pg_username" {
  value     = aiven_pg.pg.service_username
  sensitive = true
}

output "pg_password" {
  value     = aiven_pg.pg.service_password
  sensitive = true
}


