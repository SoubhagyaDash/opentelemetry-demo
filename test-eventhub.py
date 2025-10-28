#!/usr/bin/env python3
"""
Test EventHub integration by sending a test message
"""
import asyncio
import json
from azure.eventhub.aio import EventHubProducerClient
from azure.eventhub import EventData

async def send_test_message():
    connection_string = ""
    eventhub_name = "otel-events"
    
    # Create a producer client to send messages to the event hub
    producer = EventHubProducerClient.from_connection_string(
        conn_str=connection_string,
        eventhub_name=eventhub_name
    )
    
    async with producer:
        # Create a test order event similar to what checkout service would send
        test_order = {
            "user_id": "test-user-12345",
            "order_id": "test-order-67890",
            "timestamp": "2025-10-27T23:20:00Z",
            "amount": 99.99,
            "currency": "USD",
            "items": [
                {"product_id": "test-product", "quantity": 1, "price": 99.99}
            ]
        }
        
        # Create batch of events
        event_data_batch = await producer.create_batch()
        
        # Add test message to the batch
        event_data = EventData(json.dumps(test_order))
        event_data_batch.add(event_data)
        
        # Send the batch
        await producer.send_batch(event_data_batch)
        print(f"✅ Successfully sent test message to EventHub!")
        print(f"📋 Message: {json.dumps(test_order, indent=2)}")

if __name__ == "__main__":
    print("🔄 Testing EventHub integration...")
    asyncio.run(send_test_message())
    print("✨ Test completed!")