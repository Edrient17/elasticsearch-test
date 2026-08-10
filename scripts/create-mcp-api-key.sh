#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

expiration="${1:-30d}"
elastic_password="$(docker compose exec -T elasticsearch printenv ELASTIC_PASSWORD | tr -d '\r')"

curl -fsS -u "elastic:${elastic_password}" \
  -H "Content-Type: application/json" \
  -X POST "http://localhost:9200/_security/api_key?pretty" \
  -d "{
    \"name\": \"mcp-vm-logs-readonly\",
    \"expiration\": \"${expiration}\",
    \"role_descriptors\": {
      \"vm-logs-readonly\": {
        \"cluster\": [\"monitor\"],
        \"indices\": [
          {
            \"names\": [\"vm-logs-*\"],
            \"privileges\": [\"read\", \"view_index_metadata\"]
          }
        ]
      }
    }
  }"

echo
echo "Copy the 'encoded' value into ES_API_KEY. It is shown only once."
