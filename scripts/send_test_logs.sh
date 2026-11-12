#!/usr/bin/env bash
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-ca-central-1}"
LOG_GROUP="${LOG_GROUP_NAME:-/aws/application/monitoring-tool}"
STREAM="demo-$(date -u +%Y%m%dT%H%M%SZ)"
aws logs create-log-stream --log-group-name "$LOG_GROUP" --log-stream-name "$STREAM"
# Python constructs millisecond timestamps, avoiding macOS/GNU date differences.
for message in \
 'INFO Application started' \
 'ERROR Database connection failed' \
 'FAILED Imaging request synchronization' \
 'EXCEPTION Report processing exception' \
 'TIMEOUT External API request exceeded deadline'; do
 timestamp=$(python3 -c 'import time; print(int(time.time()*1000))')
 aws logs put-log-events --log-group-name "$LOG_GROUP" --log-stream-name "$STREAM" \
   --log-events "timestamp=${timestamp},message=${message}" >/dev/null
 echo "Sent: $message"
 sleep 1
done
echo "Check metric CustomApp/Monitoring / ApplicationErrors and alarm history after CloudWatch processes the events."
