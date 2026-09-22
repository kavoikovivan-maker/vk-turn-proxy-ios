package com.wdtt.client.ui

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.wdtt.client.TunnelManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

enum class KCAssistantMode(val title: String, val responseWords: Int) {
    QUICK("Быстрый", 80),
    SMART("Умный", 350),
    TEAM("Команда", 550)
}

data class KCChatMessage(val role: String, val text: String)

private class KCAssistantClient(private val context: Context) {
    private val prefs = context.getSharedPreferences("kc_assistant", Context.MODE_PRIVATE)
    private val http = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(50, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .build()

    var endpoint: String
        get() = prefs.getString("endpoint", "") ?: ""
        set(value) { prefs.edit().putString("endpoint", value.trim()).apply() }

    suspend fun reply(mode: KCAssistantMode, messages: List<KCChatMessage>): String = withContext(Dispatchers.IO) {
        val url = endpoint.trim()
        if (url.isBlank()) return@withContext localFallback(messages.lastOrNull()?.text.orEmpty())

        if (!url.startsWith("https://")) {
            return@withContext "Для GPT-сервера требуется HTTPS."
        }

        val payload = JSONObject().apply {
            put("mode", mode.name.lowercase())
            put("responseWords", mode.responseWords)
            put("network", JSONObject().apply {
                put("vpnRunning", TunnelManager.running.value)
                put("connecting", TunnelManager.isConnecting.value)
                put("workers", TunnelManager.activeWorkers.value)
                put("stats", TunnelManager.stats.value)
                put("lastError", TunnelManager.lastFatalError.value ?: "")
            })
            put("messages", JSONArray().apply {
                messages.takeLast(16).forEach { m ->
                    put(JSONObject().put("role", m.role).put("content", m.text))
                }
            })
        }

        val req = Request.Builder()
            .url(url)
            .post(payload.toString().toRequestBody("application/json".toMediaType()))
            .header("Accept", "application/json")
            .build()

        try {
            http.newCall(req).execute().use { response ->
                val body = response.body?.string().orEmpty()
                if (!response.isSuccessful) return@withContext "GPT-сервер недоступен: HTTP ${response.code}"
                val obj = runCatching { JSONObject(body) }.getOrNull()
                    ?: return@withContext "GPT-сервер вернул некорректный ответ."
                obj.optString("reply").takeIf { it.isNotBlank() }
                    ?: obj.optJSONArray("choices")
                        ?.optJSONObject(0)
                        ?.optJSONObject("message")
                        ?.optString("content")
                        ?.takeIf { it.isNotBlank() }
                    ?: "GPT-сервер не вернул текст ответа."
            }
        } catch (e: Exception) {
            "GPT-сервер недоступен: ${e.message ?: "ошибка сети"}"
        }
    }

    private fun localFallback(text: String): String {
        val lower = text.lowercase()
        return when {
            "vpn" in lower || "интернет" in lower || "сеть" in lower || "пинг" in lower ->
                "K&C локально: VPN=${if (TunnelManager.running.value) "включён" else "выключен"}, " +
                    "воркеров=${TunnelManager.activeWorkers.value}, состояние: ${TunnelManager.stats.value}."
            else ->
                "Локальный помощник работает. Для полноценного GPT укажите HTTPS-адрес K&C AI-сервера."
        }
    }
}

@Composable
fun KCAssistantTab() {
    val context = LocalContext.current
    val client = remember { KCAssistantClient(context) }
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf(KCAssistantMode.SMART) }
    var input by remember { mutableStateOf("") }
    var endpoint by remember { mutableStateOf(client.endpoint) }
    var busy by remember { mutableStateOf(false) }
    var messages by remember {
        mutableStateOf(listOf(KCChatMessage("assistant", "K&C GPT готов. Я вижу состояние VPN и могу помочь с сетью и маршрутами.")))
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text("K&C GPT", style = MaterialTheme.typography.headlineSmall)
        Text(
            if (endpoint.isBlank()) "Локальный помощник · без ИИ-сервера"
            else "GPT-сервер задан · проверяется при запросе",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            KCAssistantMode.entries.forEachIndexed { index, item ->
                SegmentedButton(
                    selected = mode == item,
                    onClick = { mode = item },
                    shape = SegmentedButtonDefaults.itemShape(index, KCAssistantMode.entries.size)
                ) { Text(item.title) }
            }
        }

        OutlinedTextField(
            value = endpoint,
            onValueChange = {
                endpoint = it
                client.endpoint = it
            },
            label = { Text("HTTPS адрес GPT-сервера") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(messages) { m ->
                Surface(
                    tonalElevation = if (m.role == "user") 2.dp else 0.dp,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        m.text,
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Сообщение") },
                enabled = !busy
            )
            Button(
                enabled = input.isNotBlank() && !busy,
                onClick = {
                    val text = input.trim()
                    input = ""
                    val next = messages + KCChatMessage("user", text)
                    messages = next
                    busy = true
                    scope.launch {
                        val answer = client.reply(mode, next)
                        messages = messages + KCChatMessage("assistant", answer)
                        busy = false
                    }
                }
            ) {
                if (busy) CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                else Text("→")
            }
        }
    }
}
