// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
package eventhub

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/messaging/azeventhubs"
)

var (
	// EventHub topic/entity name for orders
	EventHubName = "orders"
)

// EventHubProducer wraps the Azure EventHub producer client
type EventHubProducer struct {
	client    *azeventhubs.ProducerClient
	logger    *slog.Logger
	eventHubName string
}

// EventHubConfig holds configuration for EventHub connection
type EventHubConfig struct {
	NamespaceName     string // EventHub namespace name (without .servicebus.windows.net)
	EventHubName      string // EventHub entity name
	ConnectionString  string // EventHub connection string (optional, for connection string auth)
}

// CreateEventHubProducer creates a new EventHub producer using connection string or managed identity
func CreateEventHubProducer(config EventHubConfig, logger *slog.Logger) (*EventHubProducer, error) {
	if config.NamespaceName == "" {
		return nil, fmt.Errorf("EventHub namespace name is required")
	}
	
	if config.EventHubName == "" {
		config.EventHubName = EventHubName // Use default if not specified
	}

	var client *azeventhubs.ProducerClient
	var err error

	// Check if connection string is provided
	if config.ConnectionString != "" {
		logger.Info("Using EventHub connection string authentication")
		// Use connection string authentication
		client, err = azeventhubs.NewProducerClientFromConnectionString(config.ConnectionString, config.EventHubName, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create EventHub producer client with connection string: %v", err)
		}
	} else {
		logger.Info("Using DefaultAzureCredential authentication")
		// Create a DefaultAzureCredential for managed identity authentication
		cred, err := azidentity.NewDefaultAzureCredential(nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create Azure credential: %v", err)
		}

		// Construct the fully qualified namespace
		fullyQualifiedNamespace := fmt.Sprintf("%s.servicebus.windows.net", config.NamespaceName)

		// Create the EventHub producer client
		client, err = azeventhubs.NewProducerClient(fullyQualifiedNamespace, config.EventHubName, cred, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create EventHub producer client: %v", err)
		}
	}

	logger.Info("EventHub producer client created successfully", 
		slog.String("eventhub", config.EventHubName))

	return &EventHubProducer{
		client:    client,
		logger:    logger,
		eventHubName: config.EventHubName,
	}, nil
}

// SendEvent sends a message to EventHub
func (p *EventHubProducer) SendEvent(ctx context.Context, message []byte) error {
	if p.client == nil {
		return fmt.Errorf("EventHub client is not initialized")
	}

	// Create EventHub event data
	eventData := &azeventhubs.EventData{
		Body: message,
	}

	// Create a batch with the single event
	batch, err := p.client.NewEventDataBatch(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to create event batch: %v", err)
	}

	err = batch.AddEventData(eventData, nil)
	if err != nil {
		return fmt.Errorf("failed to add event to batch: %v", err)
	}

	// Send the batch
	err = p.client.SendEventDataBatch(ctx, batch, nil)
	if err != nil {
		return fmt.Errorf("failed to send event batch: %v", err)
	}

	p.logger.Info("Event sent successfully to EventHub",
		slog.String("eventhub", p.eventHubName),
		slog.Int("message_size", len(message)))

	return nil
}

// Close closes the EventHub producer client
func (p *EventHubProducer) Close(ctx context.Context) error {
	if p.client != nil {
		return p.client.Close(ctx)
	}
	return nil
}