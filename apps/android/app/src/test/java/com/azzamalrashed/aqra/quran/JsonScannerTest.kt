package com.azzamalrashed.aqra.quran

import com.azzamalrashed.aqra.TestQuran
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** The app's quick reader of the Quran data reads every value exactly as kotlinx.serialization does. */
class JsonScannerTest {
    @Test
    fun readsEveryWordExactly() {
        val bytes = TestQuran.read("qul/qpc-v4.json")
        val reference = Json.parseToJsonElement(bytes.decodeToString()).jsonObject
        val words = MushafStore.parseWords(bytes)
        assertEquals(reference.size, words.size)
        for ((word, entry) in words.zip(reference.values)) {
            val fields = entry.jsonObject
            assertEquals(fields.getValue("id").jsonPrimitive.int, word.id)
            assertEquals(fields.getValue("surah").jsonPrimitive.content.toInt(), word.surah)
            assertEquals(fields.getValue("ayah").jsonPrimitive.content.toInt(), word.ayah)
            assertEquals(fields.getValue("word").jsonPrimitive.content.toInt(), word.word)
            assertEquals(fields.getValue("text").jsonPrimitive.content, word.text)
        }
    }

    @Test
    fun readsEveryOfficialAyahExactly() {
        val bytes = TestQuran.read("kfgqpc/hafs_smart_v8.json")
        val reference = Json.parseToJsonElement(bytes.decodeToString()).jsonArray
        val ayat = MushafStore.parseOfficial(bytes)
        assertEquals(reference.size, ayat.size)
        for ((ayah, entry) in ayat.zip(reference)) {
            val fields = entry.jsonObject
            assertEquals(fields.getValue("sura_no").jsonPrimitive.int, ayah.sura_no)
            assertEquals(fields.getValue("sura_name_ar").jsonPrimitive.content, ayah.sura_name_ar)
            assertEquals(fields.getValue("aya_no").jsonPrimitive.int, ayah.aya_no)
            assertEquals(fields.getValue("page").jsonPrimitive.int, ayah.page)
            assertEquals(fields.getValue("jozz").jsonPrimitive.int, ayah.jozz)
            assertEquals(fields.getValue("aya_text").jsonPrimitive.content, ayah.aya_text)
            assertEquals(fields.getValue("aya_text_emlaey").jsonPrimitive.content, ayah.aya_text_emlaey)
        }
    }

    @Test
    fun readsEscapesAndRefusesWhatIsntJson() {
        val scanner = JsonScanner("""{"a\"b":"xA\n\\y","n":-12,"skip":[1,{"z":true},null]}""".toByteArray())
        scanner.beginObject()
        assertEquals("a\"b", scanner.nextName())
        assertEquals("xA\n\\y", scanner.nextString())
        assertEquals(true, scanner.hasNext())
        assertEquals("n", scanner.nextName())
        assertEquals(-12, scanner.nextInt())
        scanner.hasNext()
        assertEquals("skip", scanner.nextName())
        scanner.skipValue()
        assertEquals(false, scanner.hasNext())
        scanner.endObject()
        assertThrows(IllegalArgumentException::class.java) { JsonScanner("""[1.5]""".toByteArray()).apply { beginArray() }.nextInt() }
    }
}
