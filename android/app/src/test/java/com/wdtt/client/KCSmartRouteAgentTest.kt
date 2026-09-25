package com.wdtt.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KCSmartRouteAgentTest {
    private fun sample(
        id: String,
        provider: KCRelayProvider,
        available: Boolean = true,
        speed: Double = 20.0,
        rtt: Double = 100.0,
        loss: Double = 0.0,
        stability: Double = 1.0,
        at: Long = 1_000_000L
    ) = KCRouteSample(
        id = id,
        provider = provider,
        available = available,
        throughputMbps = speed,
        rttMs = rtt,
        packetLoss = loss,
        stability = stability,
        measuredAtMs = at
    )

    @Test
    fun manualModeUsesRequestedAvailableRoute() {
        val agent = KCSmartRouteAgent()
        val vk = sample("vk", KCRelayProvider.VK)
        val yandex = sample("ya", KCRelayProvider.YANDEX, speed = 40.0)

        val decision = agent.decide(
            current = vk,
            samples = listOf(vk, yandex),
            mode = KCRouteMode.MANUAL,
            manualRouteId = "ya",
            nowMs = 1_000_000L
        )

        assertEquals("ya", decision.selected?.id)
        assertTrue(decision.shouldSwitch)
    }

    @Test
    fun unavailableCurrentSwitchesImmediatelyToHealthyCandidate() {
        val agent = KCSmartRouteAgent()
        val current = sample("vk", KCRelayProvider.VK, available = false)
        val max = sample("max1", KCRelayProvider.MAX1, speed = 30.0)

        val decision = agent.decide(
            current = current,
            samples = listOf(current, max),
            nowMs = 1_000_000L
        )

        assertEquals("max1", decision.selected?.id)
        assertTrue(decision.shouldSwitch)
    }

    @Test
    fun autoModeRequiresStableWinsBeforeSwitchingHealthyCurrentRoute() {
        val agent = KCSmartRouteAgent(
            improvementThreshold = 0.10,
            minStableSamples = 3,
            minSwitchIntervalMs = 0L
        )
        val current = sample("vk", KCRelayProvider.VK, speed = 10.0, rtt = 220.0)
        val better = sample("ya", KCRelayProvider.YANDEX, speed = 80.0, rtt = 50.0)

        val first = agent.decide(current, listOf(current, better), nowMs = 1_000_000L)
        val second = agent.decide(current, listOf(current, better), nowMs = 1_000_001L)
        val third = agent.decide(current, listOf(current, better), nowMs = 1_000_002L)

        assertFalse(first.shouldSwitch)
        assertFalse(second.shouldSwitch)
        assertTrue(third.shouldSwitch)
        assertEquals("ya", third.selected?.id)
    }

    @Test
    fun autoModeRejectsHighLossRouteEvenWhenFast() {
        val agent = KCSmartRouteAgent()
        val current = sample("vk", KCRelayProvider.VK, speed = 20.0)
        val broken = sample(
            "max1",
            KCRelayProvider.MAX1,
            speed = 200.0,
            loss = 0.50,
            stability = 0.90
        )

        val decision = agent.decide(
            current = current,
            samples = listOf(current, broken),
            nowMs = 1_000_000L
        )

        assertEquals("vk", decision.selected?.id)
        assertFalse(decision.shouldSwitch)
    }
}
