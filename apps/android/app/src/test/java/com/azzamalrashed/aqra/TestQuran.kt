package com.azzamalrashed.aqra

import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.quran.QueryRow
import com.azzamalrashed.aqra.quran.QuranFiles
import com.azzamalrashed.aqra.quran.SfntFont
import java.io.File
import java.sql.DriverManager

/** The shared Quran data, read straight from the repository (shared/quran), as the app reads its assets. */
object TestQuran : QuranFiles {
    val directory = File(requireNotNull(System.getProperty("aqra.quranDir")) { "aqra.quranDir isn't set" })

    override fun exists(path: String) = File(directory, path).exists()

    override fun read(path: String) = File(directory, path).readBytes()

    override fun query(path: String, sql: String, row: (QueryRow) -> Unit) {
        DriverManager.getConnection("jdbc:sqlite:${File(directory, path).absolutePath}").use { connection ->
            connection.createStatement().use { statement ->
                val results = statement.executeQuery(sql)
                val values = object : QueryRow {
                    override fun int(column: Int) = results.getInt(column + 1)
                    override fun string(column: Int) = results.getString(column + 1).orEmpty()
                }
                while (results.next()) row(values)
            }
        }
    }

    /** Loaded once for every test that needs it. */
    val store: MushafStore by lazy { MushafStore(this) }

    private val fonts = HashMap<Int, SfntFont>()

    fun pageFont(page: Int): SfntFont = fonts.getOrPut(page) { SfntFont.fromWoff2(read(MushafStore.pageFontPath(page))) }
}
