package com.azzamalrashed.aqra.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/**
 * Reads a record another app wrote (the iOS app, or a newer version of either) without losing the whole of it to one
 * entry that can't be read: when the plain decode fails, each entry of the named lists (`"history"`, `"plan.items"`…)
 * is tried on its own, in a copy of the record with every named list otherwise empty, and the entries that fail are
 * dropped; then the record is read again. Null only when the record can't be read even so. Unknown keys are ignored
 * (see [ProgressJson]), and keys left out take their defaults.
 */
fun <T> Json.decodeLossy(serializer: KSerializer<T>, json: String, lists: List<String>): T? {
    runCatching { decodeFromString(serializer, json) }.onSuccess { return it }
    val root = runCatching { parseToJsonElement(json).jsonObject }.getOrNull() ?: return null
    val paths = lists.map { it.split('.') }
    // Every named list emptied: a probe then fails only because of the one entry it holds.
    val base = paths.fold(root) { record, path -> if (at(record, path) is JsonArray) withPath(record, path, JsonArray(emptyList())) else record }
    var cleaned = root
    for (path in paths) {
        val list = at(root, path) as? JsonArray ?: continue
        val kept = list.filter { entry ->
            runCatching { decodeFromJsonElement(serializer, withPath(base, path, JsonArray(listOf(entry)))) }.isSuccess
        }
        cleaned = withPath(cleaned, path, JsonArray(kept))
    }
    return runCatching { decodeFromJsonElement(serializer, cleaned) }.getOrNull()
}

private fun at(record: JsonObject, path: List<String>): JsonElement? =
    path.fold(record as JsonElement?) { element, key -> (element as? JsonObject)?.get(key) }

private fun withPath(record: JsonObject, path: List<String>, value: JsonElement): JsonObject {
    val key = path.first()
    val replaced = if (path.size == 1) value
    else withPath(record[key] as? JsonObject ?: JsonObject(emptyMap()), path.drop(1), value)
    return JsonObject(record + (key to replaced))
}
