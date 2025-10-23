/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

package frauddetection

import com.azure.identity.DefaultAzureCredentialBuilder
import com.azure.messaging.eventhubs.EventHubClientBuilder
import com.azure.messaging.eventhubs.EventHubConsumerClient
import com.azure.messaging.eventhubs.models.EventPosition
import com.azure.messaging.eventhubs.models.PartitionEvent
import org.apache.logging.log4j.LogManager
import org.apache.logging.log4j.Logger
import oteldemo.Demo.*
import java.time.Duration
import java.util.*
import kotlin.system.exitProcess
import dev.openfeature.contrib.providers.flagd.FlagdOptions
import dev.openfeature.contrib.providers.flagd.FlagdProvider
import dev.openfeature.sdk.Client
import dev.openfeature.sdk.EvaluationContext
import dev.openfeature.sdk.ImmutableContext
import dev.openfeature.sdk.Value
import dev.openfeature.sdk.OpenFeatureAPI

const val eventHubName = "orders"
const val consumerGroup = "fraud-detection"

private val logger: Logger = LogManager.getLogger(consumerGroup)

fun main() {
    val options = FlagdOptions.builder()
        .withGlobalTelemetry(true)
        .build()
    val flagdProvider = FlagdProvider(options)
    OpenFeatureAPI.getInstance().setProvider(flagdProvider)

    // Get EventHub configuration from environment variables
    val eventHubNamespace = System.getenv("EVENTHUB_NAMESPACE")
    if (eventHubNamespace == null) {
        println("EVENTHUB_NAMESPACE is not supplied")
        exitProcess(1)
    }

    val eventHubEntityName = System.getenv("EVENTHUB_NAME") ?: eventHubName
    val fullyQualifiedNamespace = "$eventHubNamespace.servicebus.windows.net"

    logger.info("Connecting to EventHub: $fullyQualifiedNamespace/$eventHubEntityName")

    // Create EventHub consumer using managed identity
    val credential = DefaultAzureCredentialBuilder().build()
    
    val consumer: EventHubConsumerClient = EventHubClientBuilder()
        .credential(fullyQualifiedNamespace, eventHubEntityName, credential)
        .consumerGroup(consumerGroup)
        .buildConsumerClient()

    var totalCount = 0L

    try {
        logger.info("Starting to consume events from EventHub")
        
        // Consume events from all partitions
        val partitionIds = consumer.partitionIds
        logger.info("Available partitions: $partitionIds")
        
        // For simplicity, consuming from all partitions in a blocking manner
        // In production, you'd want to consume from each partition in separate threads
        partitionIds.forEach { partitionId ->
            Thread {
                consumer.receiveFromPartition(
                    partitionId,
                    EventPosition.earliest()
                ).forEach { partitionEvent ->
                    totalCount += 1
                    
                    if (getFeatureFlagValue("eventHubQueueProblems") > 0) {
                        logger.info("FeatureFlag 'eventHubQueueProblems' is enabled, sleeping 1 second")
                        Thread.sleep(1000)
                    }
                    
                    try {
                        val eventData = partitionEvent.data
                        val orders = OrderResult.parseFrom(eventData.body)
                        logger.info("Consumed event with orderId: ${orders.orderId}, and updated total count to: $totalCount")
                    } catch (e: Exception) {
                        logger.error("Error processing event: ${e.message}", e)
                    }
                }
            }.start()
        }
        
        // Keep the main thread alive
        while (true) {
            Thread.sleep(5000)
            logger.info("Current total count: $totalCount")
        }
        
    } catch (e: Exception) {
        logger.error("Error during EventHub consumption: ${e.message}", e)
    } finally {
        consumer.close()
        logger.info("EventHub consumer closed")
    }
}

/**
* Retrieves the status of a feature flag from the Feature Flag service.
*
* @param ff The name of the feature flag to retrieve.
* @return The integer value of the feature flag, 0 if disabled or in case of errors.
*/
fun getFeatureFlagValue(ff: String): Int {
    val client = OpenFeatureAPI.getInstance().client
    // TODO: Plumb the actual session ID from the frontend via baggage?
    val uuid = UUID.randomUUID()

    val clientAttrs = mutableMapOf<String, Value>()
    clientAttrs["session"] = Value(uuid.toString())
    client.evaluationContext = ImmutableContext(clientAttrs)
    val intValue = client.getIntegerValue(ff, 0)
    return intValue
}
