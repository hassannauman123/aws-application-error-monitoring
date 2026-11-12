import json
import unittest
from lambda_handler_fixture import load_handler

handler = load_handler()

class HandlerTests(unittest.TestCase):
    def test_cloudwatch_alarm_message(self):
        alarm = {"AlarmName": "log-alarm", "NewStateValue": "ALARM", "NewStateReason": "Threshold crossed", "StateChangeTime": "2026-11-01T00:00:00Z"}
        event = {"Records": [{"Sns": {"Message": json.dumps(alarm)}}]}
        result = handler(event, None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(json.loads(result["body"])["processed"], 1)

    def test_non_json_record(self):
        event = {"Records": [{"Sns": {"Message": "not json"}}]}
        self.assertEqual(json.loads(handler(event, None)["body"])["processed"], 0)

if __name__ == '__main__':
    unittest.main()
