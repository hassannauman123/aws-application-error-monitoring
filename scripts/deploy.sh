#!/usr/bin/env bash
set -euo pipefail
: "${NOTIFICATION_EMAIL:?Set NOTIFICATION_EMAIL to your email address}"
REGION="${AWS_REGION:-ca-central-1}"
LOG_GROUP="${LOG_GROUP_NAME:-/aws/application/monitoring-tool}"
TOPIC="${SNS_TOPIC_NAME:-log-monitoring-alerts}"
FUNCTION="${LAMBDA_FUNCTION_NAME:-log-processor}"
ROLE="${IAM_ROLE_NAME:-lambda-log-processor-role}"
ALARM="${ALARM_NAME:-log-alarm}"
FILTER="${METRIC_FILTER_NAME:-common-error}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT}:${TOPIC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"
FUNCTION_ARN="arn:aws:lambda:${REGION}:${ACCOUNT}:function:${FUNCTION}"
export AWS_DEFAULT_REGION="$REGION"

if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --query 'logGroups[].logGroupName' --output text | grep -Fxq "$LOG_GROUP"; then
  aws logs create-log-group --log-group-name "$LOG_GROUP"
fi
aws logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days 7
aws sns create-topic --name "$TOPIC" >/dev/null
if ! aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query 'Subscriptions[].Endpoint' --output text | tr '\t' '\n' | grep -Fxq "$NOTIFICATION_EMAIL"; then
  aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$NOTIFICATION_EMAIL" >/dev/null
  echo 'Confirm your SNS email subscription before testing.'
fi

# CloudWatch Logs filter uses regex syntax enclosed in percent signs.
# Matches any of these uppercase terms anywhere in an incoming log event.
aws logs put-metric-filter \
 --log-group-name "$LOG_GROUP" --filter-name "$FILTER" \
 --filter-pattern '%ERROR|FAILED|EXCEPTION|TIMEOUT%' \
 --metric-transformations 'metricName=ApplicationErrors,metricNamespace=CustomApp/Monitoring,metricValue=1,defaultValue=0'

if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
fi
aws iam attach-role-policy --role-name "$ROLE" \
 --policy-arn 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'

BUILD_DIR=$(mktemp -d /tmp/cloudwatch-processor.XXXXXX)
ZIP_FILE="$BUILD_DIR/log-processor.zip"
trap 'rm -rf "$BUILD_DIR"' EXIT
(cd "$(dirname "$0")/../lambda" && zip -q "$ZIP_FILE" log_processor.py)
if aws lambda get-function --function-name "$FUNCTION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNCTION" --zip-file "fileb://$ZIP_FILE" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION"
  aws lambda update-function-configuration --function-name "$FUNCTION" --runtime python3.13 --handler log_processor.lambda_handler >/dev/null
else
  # Newly created IAM roles may take time to become available to Lambda.
  for attempt in {1..8}; do
    if aws lambda create-function --function-name "$FUNCTION" --runtime python3.13 \
      --role "$ROLE_ARN" --handler log_processor.lambda_handler \
      --zip-file "fileb://$ZIP_FILE" --timeout 30 --memory-size 128 >/dev/null; then break; fi
    if [[ "$attempt" == 8 ]]; then echo 'Lambda creation failed after retries' >&2; exit 1; fi
    sleep 5
  done
fi
aws lambda wait function-active-v2 --function-name "$FUNCTION"

aws cloudwatch put-metric-alarm --alarm-name "$ALARM" \
 --alarm-description 'More than two matching application log errors within five minutes' \
 --alarm-actions "$TOPIC_ARN" --metric-name ApplicationErrors \
 --namespace CustomApp/Monitoring --statistic Sum --period 300 \
 --threshold 2 --comparison-operator GreaterThanThreshold \
 --evaluation-periods 1 --datapoints-to-alarm 1 --treat-missing-data notBreaching

# Allow only this SNS topic to invoke the function.
if ! aws lambda get-policy --function-name "$FUNCTION" --query Policy --output text 2>/dev/null | grep -q 'sns-trigger'; then
  aws lambda add-permission --function-name "$FUNCTION" --statement-id sns-trigger \
   --action lambda:InvokeFunction --principal sns.amazonaws.com --source-arn "$TOPIC_ARN" >/dev/null
fi
if ! aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
 --query 'Subscriptions[].Endpoint' --output text | tr '\t' '\n' | grep -Fxq "$FUNCTION_ARN"; then
  aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol lambda \
    --notification-endpoint "$FUNCTION_ARN" >/dev/null
fi
printf 'Deployment configured in %s\nLog group: %s\nSNS topic: %s\nAlarm: %s\nLambda: %s\n' "$REGION" "$LOG_GROUP" "$TOPIC_ARN" "$ALARM" "$FUNCTION"
