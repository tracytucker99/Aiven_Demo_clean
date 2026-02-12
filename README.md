# Aiven_Demo_clean — Interview Take-Home: Real-time Clickstream → Kafka → PostgreSQL → (Optional) OpenSearch

This repository is an end-to-end technical demo that shows how to:
- Ingest website clickstream events into Aiven for Apache Kafka
- Consume and sessionize/aggregate events into Aiven for PostgreSQL
- Optionally index into Aiven for OpenSearch for analytics/search use cases

## Repo layout
- app/       Node/TypeScript app (producer + consumer)
- terraform/ Terraform to provision Aiven services
- sql/       Schema + queries
- scripts/   Optional helper scripts
- bin/       Optional helper scripts

## Security: never commit
- .env, app/.env, .env.* backups
- terraform/terraform.tfstate*
- terraform/.terraform/
- node_modules/ (root or app)

## Prerequisites
- Node.js 20+ and npm
- Terraform 1.5+
- Aiven account + project with credits
- Optional: Aiven CLI (avn)

## Quick start

1) Install dependencies
npm install
cd app
npm install
cd ..

2) Configure environment
cp .env.example .env
cp .env.example app/.env

3) Provision infrastructure
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
cd ..

4) Initialize PostgreSQL schema
psql "$PG_DSN" -f sql/schema.sql

5) Run producer
npm run run:producer

6) Run consumer (new terminal)
npm run run:consumer

7) Kafka smoke test (optional)
npm run smoke:kafka

## Demo checklist
- Show Terraform resources created
- Show producer logs (events flowing)
- Show consumer logs (session aggregates)
- Query Postgres to show results
- Optional: show OpenSearch index/dashboard

## Troubleshooting

GitHub blocked pushes (secrets)
- Remove tracked secret files and rewrite history or use a clean repo
- Rotate the secret in Aiven if it was exposed

TLS / certificate issues
- Ensure correct CA cert and SSL settings for Aiven services

Terraform invalid service plan
- Update plan names in terraform/main.tf to match your Aiven project

## npm scripts (root)
- npm run run:producer
- npm run run:consumer
- npm run smoke:kafka
