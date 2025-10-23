// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

using Azure.Identity;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Consumer;
using Microsoft.Extensions.Logging;
using Oteldemo;
using Microsoft.EntityFrameworkCore;
using System.Diagnostics;

namespace Accounting;

internal class DBContext : DbContext
{
    public DbSet<OrderEntity> Orders { get; set; }
    public DbSet<OrderItemEntity> CartItems { get; set; }
    public DbSet<ShippingEntity> Shipping { get; set; }

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        var connectionString = Environment.GetEnvironmentVariable("DB_CONNECTION_STRING");

        optionsBuilder.UseNpgsql(connectionString).UseSnakeCaseNamingConvention();
    }
}


internal class Consumer : IDisposable
{
    private const string EventHubName = "orders";
    private const string ConsumerGroup = "accounting";

    private readonly ILogger _logger;
    private EventHubConsumerClient? _consumer;
    private bool _isListening;
    private DBContext? _dbContext;
    private static readonly ActivitySource MyActivitySource = new("Accounting.Consumer");
    private CancellationTokenSource? _cancellationTokenSource;

    public Consumer(ILogger<Consumer> logger)
    {
        _logger = logger;

        var eventHubNamespace = Environment.GetEnvironmentVariable("EVENTHUB_NAMESPACE")
            ?? throw new ArgumentNullException("EVENTHUB_NAMESPACE");

        var eventHubEntityName = Environment.GetEnvironmentVariable("EVENTHUB_NAME") ?? EventHubName;
        var fullyQualifiedNamespace = $"{eventHubNamespace}.servicebus.windows.net";

        _consumer = BuildConsumer(fullyQualifiedNamespace, eventHubEntityName);

        _logger.LogInformation($"Connecting to EventHub: {fullyQualifiedNamespace}/{eventHubEntityName}");
        _dbContext = Environment.GetEnvironmentVariable("DB_CONNECTION_STRING") == null ? null : new DBContext();
        _cancellationTokenSource = new CancellationTokenSource();
    }

    public async Task StartListeningAsync()
    {
        _isListening = true;

        if (_consumer == null)
        {
            _logger.LogError("EventHub consumer is not initialized");
            return;
        }

        try
        {
            await foreach (PartitionEvent partitionEvent in _consumer.ReadEventsAsync(_cancellationTokenSource?.Token ?? CancellationToken.None))
            {
                if (!_isListening)
                    break;

                try
                {
                    using var activity = MyActivitySource.StartActivity("order-consumed", ActivityKind.Internal);
                    ProcessMessage(partitionEvent.Data);
                }
                catch (Exception e)
                {
                    _logger.LogError(e, "Event processing error: {0}", e.Message);
                }
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("EventHub consumer operation was cancelled");
        }
        catch (Exception e)
        {
            _logger.LogError(e, "Error reading events from EventHub: {0}", e.Message);
        }
        finally
        {
            _logger.LogInformation("Closing EventHub consumer");
        }
    }

    public void StartListening()
    {
        // Keep synchronous interface for backward compatibility
        Task.Run(async () => await StartListeningAsync()).Wait();
    }

    private void ProcessMessage(EventData eventData)
    {
        try
        {
            var order = OrderResult.Parser.ParseFrom(eventData.Body.ToArray());
            Log.OrderReceivedMessage(_logger, order);

            if (_dbContext == null)
            {
                return;
            }

            var orderEntity = new OrderEntity
            {
                Id = order.OrderId
            };
            _dbContext.Add(orderEntity);
            foreach (var item in order.Items)
            {
                var orderItem = new OrderItemEntity
                {
                    ItemCostCurrencyCode = item.Cost.CurrencyCode,
                    ItemCostUnits = item.Cost.Units,
                    ItemCostNanos = item.Cost.Nanos,
                    ProductId = item.Item.ProductId,
                    Quantity = item.Item.Quantity,
                    OrderId = order.OrderId
                };

                _dbContext.Add(orderItem);
            }

            var shipping = new ShippingEntity
            {
                ShippingTrackingId = order.ShippingTrackingId,
                ShippingCostCurrencyCode = order.ShippingCost.CurrencyCode,
                ShippingCostUnits = order.ShippingCost.Units,
                ShippingCostNanos = order.ShippingCost.Nanos,
                StreetAddress = order.ShippingAddress.StreetAddress,
                City = order.ShippingAddress.City,
                State = order.ShippingAddress.State,
                Country = order.ShippingAddress.Country,
                ZipCode = order.ShippingAddress.ZipCode,
                OrderId = order.OrderId
            };
            _dbContext.Add(shipping);
            _dbContext.SaveChanges();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Order parsing failed:");
        }
    }

    private EventHubConsumerClient BuildConsumer(string fullyQualifiedNamespace, string eventHubName)
    {
        // Use DefaultAzureCredential for managed identity authentication
        var credential = new DefaultAzureCredential();

        return new EventHubConsumerClient(
            ConsumerGroup,
            fullyQualifiedNamespace,
            eventHubName,
            credential);
    }

    public void Dispose()
    {
        _isListening = false;
        _cancellationTokenSource?.Cancel();
        _consumer?.DisposeAsync().AsTask().Wait();
        _cancellationTokenSource?.Dispose();
        _dbContext?.Dispose();
    }
}
