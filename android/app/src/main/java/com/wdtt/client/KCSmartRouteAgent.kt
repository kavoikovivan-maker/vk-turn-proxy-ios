package com.wdtt.client

import kotlin.math.max

enum class KCRelayProvider(val title: String) {
    VK("VK"),
    MAX1("Max 1"),
    MAX2("Max 2"),
    YANDEX("Yandex"),
    VPN("VPN")
}

data class KCRouteSample(
    val id: String,
    val provider: KCRelayProvider,
    val country: String = "",
    val available: Boolean,
    val throughputMbps: Double,
    val rttMs: Double,
    val packetLoss: Double,
    val stability: Double,
    val measuredAtMs: Long = System.currentTimeMillis()
)

data class KCRouteDecision(
    val selected: KCRouteSample?,
    val reason: String,
    val shouldSwitch: Boolean
)

/**
 * Deterministic Smart Route policy shared by the Android UI/service.
 *
 * Priority:
 * 1. unavailable routes are removed;
 * 2. packet loss / stability can veto a fast but broken path;
 * 3. throughput is the main positive signal;
 * 4. RTT breaks close ties;
 * 5. current route is kept unless a candidate is materially better.
 */
class KCSmartRouteAgent(
    private val improvementThreshold: Double = 0.18,
    private val minStableSamples: Int = 3,
    private val minSwitchIntervalMs: Long = 60_000L
) {
    private var candidateWins = 0
    private var lastCandidateId: String? = null
    private var lastSwitchAt = 0L

    fun decide(current: KCRouteSample?, samples: List<KCRouteSample>, nowMs: Long = System.currentTimeMillis()): KCRouteDecision {
        val viable = samples
            .filter { it.available }
            .filter { nowMs - it.measuredAtMs <= 30_000L }
            .filter { it.packetLoss <= 0.25 }
            .filter { it.stability >= 0.45 }

        if (viable.isEmpty()) {
            candidateWins = 0
            lastCandidateId = null
            return KCRouteDecision(current, "Нет измеренного доступного маршрута", false)
        }

        val best = viable.maxByOrNull(::score)!!
        if (current == null || !current.available) {
            return KCRouteDecision(best, "Текущий маршрут недоступен", true)
        }
        if (best.id == current.id) {
            candidateWins = 0
            lastCandidateId = null
            return KCRouteDecision(current, "Текущий маршрут остаётся лучшим", false)
        }

        val currentScore = score(current).coerceAtLeast(0.01)
        val gain = (score(best) - currentScore) / currentScore
        if (gain < improvementThreshold) {
            candidateWins = 0
            lastCandidateId = null
            return KCRouteDecision(current, "Разница меньше ${(improvementThreshold * 100).toInt()}%", false)
        }

        if (lastCandidateId == best.id) candidateWins++ else {
            lastCandidateId = best.id
            candidateWins = 1
        }

        if (nowMs - lastSwitchAt < minSwitchIntervalMs) {
            return KCRouteDecision(current, "Защита от частых переключений", false)
        }
        if (candidateWins < minStableSamples) {
            return KCRouteDecision(current, "Проверяю ${best.provider.title}: ${candidateWins}/${minStableSamples}", false)
        }

        lastSwitchAt = nowMs
        candidateWins = 0
        lastCandidateId = null
        return KCRouteDecision(
            best,
            "Переключение: ${best.provider.title} ${"%.1f".format(best.throughputMbps)} Мбит/с, ${best.rttMs.toInt()} мс",
            true
        )
    }

    private fun score(s: KCRouteSample): Double {
        if (!s.available) return Double.NEGATIVE_INFINITY
        val speed = max(0.0, s.throughputMbps)
        val latencyFactor = 1.0 / (1.0 + max(0.0, s.rttMs) / 180.0)
        val lossFactor = (1.0 - s.packetLoss.coerceIn(0.0, 1.0))
        val stable = s.stability.coerceIn(0.0, 1.0)
        return speed * 0.70 + (100.0 * latencyFactor) * 0.12 + (100.0 * lossFactor) * 0.10 + (100.0 * stable) * 0.08
    }
}
