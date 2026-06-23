import json
import datetime


def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Olá mundo do EKS lab!",
            "from": "AWS Lambda + API Gateway",
            "time": datetime.datetime.utcnow().isoformat() + "Z",
        }),
    }
