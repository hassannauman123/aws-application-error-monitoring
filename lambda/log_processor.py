"""Process CloudWatch alarm notifications delivered through Amazon SNS."""
import json
import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    processed = 0
    for record in event.get("Records", []):
        sns = record.get("Sns", {})
        raw_message = sns.get("Message", "")
        try:
            message = json.loads(raw_message)
        except (ValueError, TypeError):
            logger.warning("Skipping SNS record containing non-JSON alarm message")
            continue
        if not isinstance(message, dict):
            logger.warning("Skipping unexpected SNS JSON payload")
            continue
        summary = {
            "alarm_name": message.get("AlarmName", "Unknown"),
            "state": message.get("NewStateValue", "Unknown"),
            "reason": message.get("NewStateReason", "No reason provided"),
            "timestamp": message.get("StateChangeTime", datetime.now(timezone.utc).isoformat()),
        }
        logger.info("Processed CloudWatch alarm notification: %s", json.dumps(summary))
        processed += 1
    return {"statusCode": 200, "body": json.dumps({"processed": processed})}
