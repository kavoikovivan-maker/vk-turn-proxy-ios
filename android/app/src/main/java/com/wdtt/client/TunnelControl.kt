package com.wdtt.client

import android.content.Context
import android.content.Intent
import android.os.Build
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

object TunnelControl {

    fun stop(context: Context) {
        val stopIntent = Intent(context, TunnelService::class.java).apply { action = "STOP" }
        context.startService(stopIntent)
    }

    fun startFromSavedSettings(context: Context) {
        val appContext = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch {
            SettingsStore.awaitMigrations(appContext)
            val store = SettingsStore(appContext)
            val basePeer = store.peer.first()
            val hashes = store.vkHashes.first()
            val relayProvider = store.relayProvider.first()
            val maxToken = store.maxToken.first()
            val maxCalleeUid = store.maxCalleeUid.first()
            val max2CalleeUid = store.max2CalleeUid.first()
            val yandexTelemostLink = store.yandexTelemostLink.first()
            val workers = store.workersPerHash.first()
            val port = store.listenPort.first()
            val password = store.connectionPassword.first()
            val captchaMode = store.captchaMode.first()
            val captchaMethod = store.captchaSolveMethod.first()
            val vkAnonPath = SettingsStore.normalizeVkAnonPath(store.vkAnonPath.first())
            val goDnsArg = store.resolveGoDnsArg()
            val obfsMode = SettingsStore.normalizeObfsMode(store.obfsMode.first())
            val connectionMode = SettingsStore.normalizeConnectionMode(store.connectionMode.first())
            val socksPort = SettingsStore.normalizeSocksPort(store.socksPort.first())
            val manualPortsEnabled = store.manualPortsEnabled.first()
            val serverDtlsPort = if (manualPortsEnabled) store.serverDtlsPort.first() else 56000
            val peerWithPort = if (basePeer.isBlank()) basePeer else PeerAddress.ensurePort(basePeer, serverDtlsPort)

            val relayReady = when (relayProvider.lowercase()) {
                "auto" -> hashes.isNotBlank() ||
                    (maxToken.isNotBlank() &&
                        (maxCalleeUid.isNotBlank() || max2CalleeUid.isNotBlank())) ||
                    yandexTelemostLink.isNotBlank()
                "max1" -> maxToken.isNotBlank() && maxCalleeUid.isNotBlank()
                "max2" -> maxToken.isNotBlank() &&
                    (max2CalleeUid.isNotBlank() || maxCalleeUid.isNotBlank())
                "yandex" -> yandexTelemostLink.isNotBlank()
                else -> hashes.isNotBlank()
            }

            if (peerWithPort.isBlank() || !relayReady || password.isBlank()) {
                return@launch
            }

            val startIntent = Intent(appContext, TunnelService::class.java).apply {
                action = "START_FORCED"
                putExtra("peer", peerWithPort)
                putExtra("vk_hashes", hashes)
                putExtra("secondary_vk_hash", "")
                putExtra("workers_per_hash", workers)
                putExtra("port", port)
                putExtra("sni", store.sni.first())
                putExtra("connection_password", password)
                putExtra("captcha_mode", captchaMode)
                putExtra("captcha_solve_method", captchaMethod)
                putExtra("vk_anon_path", vkAnonPath)
                putExtra("go_dns_arg", goDnsArg)
                putExtra("obfs_mode", obfsMode)
                putExtra("connection_mode", connectionMode)
                putExtra("socks_port", socksPort)
                putExtra("relay_provider", relayProvider)
                putExtra("max_token", maxToken)
                putExtra("max_callee_uid", maxCalleeUid)
                putExtra("max2_callee_uid", max2CalleeUid)
                putExtra("yandex_telemost_link", yandexTelemostLink)
            }

            withContext(Dispatchers.Main) {
                if (Build.VERSION.SDK_INT >= 26) {
                    appContext.startForegroundService(startIntent)
                } else {
                    appContext.startService(startIntent)
                }
            }
        }
    }
}
