variable "aiven_api_token" {
  type      = string
  sensitive = true
}

variable "project" {
  type = string
}

variable "cloud" {
  type    = string
  default = "aws-us-east-2"
}

variable "kafka_plan" {
  type    = string
  default = "startup-4"
}

variable "pg_plan" {
  type    = string
  default = "startup-4"
}

variable "opensearch_plan" {
  type    = string
  default = "startup-4"
}

variable "kafka_service_name" {
  type    = string
  default = "demo-kafka"
}

variable "pg_service_name" {
  type    = string
  default = "demo-pg"
}

variable "opensearch_service_name" {
  type    = string
  default = "demo-opensearch"
}

variable "topic_name" {
  type    = string
  default = "clickstream.events"
}

variable "topic_partitions" {
  type    = number
  default = 3
}

variable "topic_retention_ms" {
  type    = number
  default = 604800000
}

