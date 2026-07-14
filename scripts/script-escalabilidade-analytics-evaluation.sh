#!/bin/bash

URL="http://a2ddbc573bab84dfb9d89a9e253f10af-630546798.us-east-1.elb.amazonaws.com/evaluate/evaluate"

echo "=== Sending 3000 evaluate requests ==="
for i in $(seq 1 3000); do
  curl -s "$URL?user_id=user-$i&flag_name=my-flag" \
    -H "Authorization: Bearer $TM_KEY" > /dev/null &
  echo "Request $i"
done

echo "=== Sending 500 SQS messages ==="
for i in $(seq 1 500); do
  aws sqs send-message \
    --queue-url https://sqs.us-east-1.amazonaws.com/947200280006/togglemaster \
    --message-body "{\"flag_name\":\"my-flag\",\"user_id\":\"user-$i\",\"result\":true,\"timestamp\":\"2026-07-08T00:00:00Z\"}" \
    --region us-east-1
done
