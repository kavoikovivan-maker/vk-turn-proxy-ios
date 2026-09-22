package com.wdtt.client

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

data class KCTurnCredentials(
    val urls: List<String>,
    val username: String,
    val credential: String
) {
    fun udpAddresses(): List<String> = urls.mapNotNull { raw ->
        if (!raw.startsWith("turn:") && !raw.startsWith("turns:")) return@mapNotNull null
        if (raw.contains("transport=tcp", ignoreCase = true)) return@mapNotNull null
        raw.substringBefore("?")
            .removePrefix("turn:")
            .removePrefix("turns:")
            .removePrefix("//")
            .takeIf { it.isNotBlank() }
    }
}

object KCTurnParser {
    fun fromJson(value: Any?): KCTurnCredentials? {
        when (value) {
            is JSONObject -> {
                val direct = fromObject(value)
                if (direct != null) return direct

                val priority = listOf(
                    "turn_server", "turn", "rtcConfiguration",
                    "iceServers", "serverHello", "conversationParams"
                )
                for (key in priority) {
                    if (value.has(key)) {
                        val found = fromJson(value.opt(key))
                        if (found != null) return found
                    }
                }
                val keys = value.keys()
                while (keys.hasNext()) {
                    val found = fromJson(value.opt(keys.next()))
                    if (found != null) return found
                }
            }
            is JSONArray -> for (i in 0 until value.length()) {
                val found = fromJson(value.opt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun fromObject(obj: JSONObject): KCTurnCredentials? {
        val user = obj.optString("username")
        val pass = obj.optString("credential")
        if (user.isBlank() || pass.isBlank() || !obj.has("urls")) return null

        val urls = mutableListOf<String>()
        when (val raw = obj.opt("urls")) {
            is JSONArray -> for (i in 0 until raw.length()) {
                raw.optString(i).takeIf { it.isNotBlank() }?.let(urls::add)
            }
            is String -> if (raw.isNotBlank()) urls += raw
        }
        if (urls.none { it.startsWith("turn:") || it.startsWith("turns:") }) return null
        return KCTurnCredentials(urls, user, pass)
    }
}

object KCYandexTurnProvider {
    private const val UA =
        "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/146 Mobile Safari/537.36"

    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    suspend fun fetch(telemostLink: String): Result<KCTurnCredentials> = withContext(Dispatchers.IO) {
        runCatching {
            val id = conferenceId(telemostLink)
                ?: error("Некорректная ссылка Yandex Telemost")
            val encoded = URLEncoder.encode(
                "https://telemost.yandex.ru/j/" + id,
                Charsets.UTF_8.name()
            )
            val url =
                "https://cloud-api.yandex.ru/telemost_front/v2/telemost/conferences/" +
                    encoded + "/connection?next_gen_media_platform_allowed=false"

            val req = Request.Builder()
                .url(url)
                .header("User-Agent", UA)
                .header("Referer", "https://telemost.yandex.ru/")
                .header("Origin", "https://telemost.yandex.ru")
                .header("Client-Instance-Id", UUID.randomUUID().toString())
                .build()

            val conf = http.newCall(req).execute().use { response ->
                if (!response.isSuccessful) error("Yandex HTTP " + response.code)
                JSONObject(response.body?.string().orEmpty())
            }

            val roomId = conf.optString("room_id")
            val peerId = conf.optString("peer_id")
            val credentials = conf.optString("credentials")
            val wsUrl = conf.optJSONObject("client_configuration")
                ?.optString("media_server_url").orEmpty()

            if (roomId.isBlank() || peerId.isBlank() || credentials.isBlank() || wsUrl.isBlank()) {
                error("Yandex не вернул параметры конференции")
            }

            fetchFromWebSocket(wsUrl, roomId, peerId, credentials).getOrThrow()
        }
    }

    private suspend fun fetchFromWebSocket(
        wsUrl: String,
        roomId: String,
        peerId: String,
        credentials: String
    ): Result<KCTurnCredentials> = suspendCancellableCoroutine { continuation ->
        val request = Request.Builder()
            .url(wsUrl)
            .header("Origin", "https://telemost.yandex.ru")
            .header("User-Agent", UA)
            .build()

        var socket: WebSocket? = null
        socket = http.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                val hello = JSONObject()
                    .put("uid", UUID.randomUUID().toString())
                    .put("hello", JSONObject()
                        .put("participantMeta", JSONObject()
                            .put("name", "Guest")
                            .put("role", "SPEAKER")
                            .put("description", "")
                            .put("sendAudio", false)
                            .put("sendVideo", false))
                        .put("participantAttributes", JSONObject()
                            .put("name", "Guest")
                            .put("role", "SPEAKER")
                            .put("description", ""))
                        .put("sendAudio", false)
                        .put("sendVideo", false)
                        .put("sendSharing", false)
                        .put("participantId", peerId)
                        .put("roomId", roomId)
                        .put("serviceName", "telemost")
                        .put("credentials", credentials)
                        .put("sdkInfo", JSONObject()
                            .put("implementation", "browser")
                            .put("version", "5.15.0")
                            .put("userAgent", UA)
                            .put("hwConcurrency", 4))
                        .put("sdkInitializationId", UUID.randomUUID().toString())
                        .put("disablePublisher", false)
                        .put("disableSubscriber", false)
                    )
                webSocket.send(hello.toString())
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                val found = runCatching { KCTurnParser.fromJson(JSONObject(text)) }.getOrNull()
                if (found != null && continuation.isActive) {
                    continuation.resume(Result.success(found))
                    webSocket.close(1000, "done")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (continuation.isActive) continuation.resume(Result.failure(t))
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (continuation.isActive) {
                    continuation.resume(Result.failure(IllegalStateException("Yandex TURN не получен")))
                }
            }
        })
        continuation.invokeOnCancellation { socket?.cancel() }
    }

    private fun conferenceId(input: String): String? {
        val value = input.trim()
        if (value.isBlank()) return null
        val tail = if ("/j/" in value) value.substringAfter("/j/") else value
        return tail.substringBefore("?").substringBefore("#").substringBefore("/")
            .takeIf { it.isNotBlank() }
    }
}

object KCMaxTurnProvider {
    private const val WS_URL = "wss://ws-api.oneme.ru/websocket"
    private const val CALLS_URL = "https://calls.okcdn.ru/fb.do"
    private const val APP_KEY = "CNHIJPLGDIHBABABA"
    private const val UA =
        "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/146 Mobile Safari/537.36"

    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    suspend fun fetch(oneMeToken: String, calleeUid: String): Result<KCTurnCredentials> =
        withContext(Dispatchers.IO) {
            runCatching {
                require(oneMeToken.isNotBlank()) { "Не указан токен MAX" }
                require(calleeUid.isNotBlank()) { "Не указан MAX ID для звонка" }

                val callToken = fetchCallToken(oneMeToken).getOrThrow()
                val login = postForm(
                    CALLS_URL,
                    mapOf(
                        "method" to "auth.anonymLogin",
                        "format" to "JSON",
                        "application_key" to APP_KEY,
                        "session_data" to JSONObject()
                            .put("auth_token", callToken)
                            .put("client_type", "SDK_JS")
                            .put("client_version", "1.1")
                            .put("device_id", UUID.randomUUID().toString())
                            .put("version", 3)
                            .toString()
                    )
                )

                val sessionKey = login.optString("session_key")
                val apiServer = login.optString("api_server").ifBlank { CALLS_URL }
                if (sessionKey.isBlank()) error("MAX не вернул session_key")

                val endpoint = if (apiServer.endsWith("fb.do")) apiServer
                    else apiServer.trimEnd('/') + "/fb.do"

                val started = postForm(
                    endpoint,
                    mapOf(
                        "method" to "vchat.startConversation",
                        "format" to "JSON",
                        "application_key" to APP_KEY,
                        "conversationId" to UUID.randomUUID().toString(),
                        "isVideo" to "false",
                        "protocolVersion" to "5",
                        "payload" to JSONObject().put("is_video", false).toString(),
                        "externalIds" to calleeUid,
                        "session_key" to sessionKey
                    )
                )

                KCTurnParser.fromJson(started)
                    ?: error("MAX не вернул TURN параметры")
            }
        }

    private suspend fun fetchCallToken(token: String): Result<String> =
        suspendCancellableCoroutine { continuation ->
            var seq = 0
            var socket: WebSocket? = null

            fun message(opcode: Int, payload: JSONObject): Pair<Int, String> {
                val current = seq++
                return current to JSONObject()
                    .put("seq", current)
                    .put("opcode", opcode)
                    .put("payload", payload)
                    .put("ver", 11)
                    .put("cmd", 0)
                    .toString()
            }

            var helloSeq = -1
            var syncSeq = -1
            var tokenSeq = -1

            val req = Request.Builder()
                .url(WS_URL)
                .header("User-Agent", UA)
                .header("Origin", "https://web.max.ru")
                .build()

            socket = http.newWebSocket(req, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    val pair = message(6, JSONObject()
                        .put("userAgent", JSONObject()
                            .put("deviceType", "WEB")
                            .put("locale", "ru")
                            .put("deviceLocale", "ru")
                            .put("osVersion", "Android")
                            .put("deviceName", "K&C")
                            .put("headerUserAgent", UA)
                            .put("appVersion", "26.4.1")
                            .put("screen", "1080x1920 1.0x")
                            .put("timezone", "Europe/Moscow"))
                        .put("deviceId", UUID.randomUUID().toString()))
                    helloSeq = pair.first
                    webSocket.send(pair.second)
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    val obj = runCatching { JSONObject(text) }.getOrNull() ?: return
                    val responseSeq = obj.optInt("seq", -999)
                    when (responseSeq) {
                        helloSeq -> {
                            val pair = message(19, JSONObject()
                                .put("token", token)
                                .put("interactive", false)
                                .put("chatsCount", 40)
                                .put("chatsSync", 0)
                                .put("contactsSync", 0)
                                .put("presenceSync", 0)
                                .put("draftsSync", 0))
                            syncSeq = pair.first
                            webSocket.send(pair.second)
                        }
                        syncSeq -> {
                            val pair = message(158, JSONObject())
                            tokenSeq = pair.first
                            webSocket.send(pair.second)
                        }
                        tokenSeq -> {
                            val callToken = obj.optJSONObject("payload")?.optString("token").orEmpty()
                            if (callToken.isNotBlank() && continuation.isActive) {
                                continuation.resume(Result.success(callToken))
                                webSocket.close(1000, "done")
                            }
                        }
                    }
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    if (continuation.isActive) continuation.resume(Result.failure(t))
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    if (continuation.isActive) {
                        continuation.resume(Result.failure(IllegalStateException("MAX call-token не получен")))
                    }
                }
            })

            continuation.invokeOnCancellation { socket?.cancel() }
        }

    private fun postForm(url: String, params: Map<String, String>): JSONObject {
        val body = FormBody.Builder().apply {
            params.forEach { (key, value) -> add(key, value) }
        }.build()
        val request = Request.Builder()
            .url(url)
            .post(body)
            .header("User-Agent", UA)
            .build()
        return http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("MAX HTTP " + response.code)
            JSONObject(response.body?.string().orEmpty())
        }
    }
}


data class KCAutoRelaySelection(
    val provider: String,
    val credentials: KCTurnCredentials,
    val discoveryMs: Long
)

/**
 * Auto preflight for configured non-VK relay providers.
 *
 * It measures the end-to-end credential discovery latency for every configured
 * MAX/Yandex route and returns the quickest successful route. VK stays the
 * fallback in TunnelManager because VK credential discovery is performed by the
 * Go core and therefore cannot be safely probed here without starting a second
 * VK session/captcha flow.
 */
object KCRelayAutoSelector {
    suspend fun select(params: TunnelParams): KCAutoRelaySelection? {
        val attempts = mutableListOf<KCAutoRelaySelection>()

        suspend fun tryProvider(name: String, block: suspend () -> Result<KCTurnCredentials>) {
            val started = android.os.SystemClock.elapsedRealtime()
            val result = runCatching { block().getOrThrow() }
            val elapsed = android.os.SystemClock.elapsedRealtime() - started
            result.getOrNull()?.let { creds ->
                if (creds.udpAddresses().isNotEmpty()) {
                    attempts += KCAutoRelaySelection(name, creds, elapsed)
                }
            }
        }

        if (params.maxToken.isNotBlank() && params.maxCalleeUid.isNotBlank()) {
            tryProvider("max1") {
                KCMaxTurnProvider.fetch(params.maxToken, params.maxCalleeUid)
            }
        }
        if (params.maxToken.isNotBlank() &&
            (params.max2CalleeUid.isNotBlank() || params.maxCalleeUid.isNotBlank())) {
            val uid = params.max2CalleeUid.ifBlank { params.maxCalleeUid }
            tryProvider("max2") {
                KCMaxTurnProvider.fetch(params.maxToken, uid)
            }
        }
        if (params.yandexTelemostLink.isNotBlank()) {
            tryProvider("yandex") {
                KCYandexTurnProvider.fetch(params.yandexTelemostLink)
            }
        }

        return attempts.minByOrNull { it.discoveryMs }
    }
}
