package com.azzamalrashed.aqra.quran

import com.azzamalrashed.aqra.TestQuran
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.security.MessageDigest

/** Guards the bundled Quran data (shared/quran) against any change: the SHA-256 values in shared/quran/README.md. */
class QuranDataTest {
    private fun sha256(file: File): String =
        MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }

    @Test
    fun filesMatchTheirRecordedChecksums() {
        val expected = mapOf(
            "kfgqpc/hafs_smart_v8.json" to "a272a119a4272f10cf42d8e389857b469183d3217fa23aa38b6a7331d0ac4aa2",
            "kfgqpc/HafsSmart_08.ttf" to "18c5641d1a9433499660122eccc6388bf89b9c8b752e5957aff41a2bed2c976b",
            "qul/qpc-v4-tajweed-15-lines.db" to "4b3fb1cbe8dff749ab0173c4b86cb40fe3c48dd072f41d3c7e715654a9f843cd",
            "qul/qpc-v4.json" to "40964a1b7932e9a69e0dfc0d58dce3b73e30a803febda119fd6828bcb75fac98",
            "qul/QCF_SurahHeader_COLOR-Regular.ttf" to "de261a309bdd42262e1a268d5ead56b6ea8366cd59124baedea3903561d7370b",
            "qul/surah-header-ligatures.json" to "c4480a1fb616685421ada1f9cbd36187c1c27c01d8d78d27a866858fdaf5c4f7",
            "qul/ayah-themes.db" to "b3c20c4fab472586904543ed12c87e2ac616ce629ac18a125357408e50927a42",
            "qcf4.sha256" to "7d2034c4e65b69b01337be804c9fb5934dee6b03b1b2e05f4fe9ec69810f28e2",
        )
        for ((path, sha) in expected) assertEquals(path, sha, sha256(File(TestQuran.directory, path)))
    }

    /** Every page font matches the manifest, and all 604 are present. */
    @Test
    fun pageFontsMatchTheManifest() {
        val entries = File(TestQuran.directory, "qcf4.sha256").readLines().filter { it.isNotBlank() }
            .map { it.trim().split(Regex("\\s+")) }
        assertEquals(MushafStore.PAGE_COUNT, entries.size)
        for ((sha, name) in entries) assertEquals(name, sha, sha256(File(TestQuran.directory, "qcf4/$name")))
    }
}
