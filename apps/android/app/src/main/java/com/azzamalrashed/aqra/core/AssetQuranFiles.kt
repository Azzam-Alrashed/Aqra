package com.azzamalrashed.aqra.core

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import com.azzamalrashed.aqra.quran.QueryRow
import com.azzamalrashed.aqra.quran.QuranFiles
import java.io.File

/**
 * The Quran data bundled in the app's assets (`assets/quran`, copied from `shared/quran` at build time). SQLite reads
 * only real files, so the two layout databases are copied out once, as they are, the first time they're needed.
 */
class AssetQuranFiles(private val context: Context) : QuranFiles {
    private val listings = HashMap<String, Set<String>>()

    @Synchronized
    override fun exists(path: String): Boolean {
        val directory = path.substringBeforeLast('/', "")
        val listing = listings.getOrPut(directory) {
            context.assets.list(if (directory.isEmpty()) "quran" else "quran/$directory").orEmpty().toSet()
        }
        return path.substringAfterLast('/') in listing
    }

    override fun read(path: String): ByteArray = context.assets.open("quran/$path").use { it.readBytes() }

    override fun query(path: String, sql: String, row: (QueryRow) -> Unit) {
        val database = SQLiteDatabase.openDatabase(copiedOut(path).path, null, SQLiteDatabase.OPEN_READONLY)
        database.use { db ->
            db.rawQuery(sql, null).use { cursor ->
                val values = object : QueryRow {
                    override fun int(column: Int) = if (cursor.isNull(column)) 0 else cursor.getString(column).toIntOrNull() ?: cursor.getInt(column)
                    override fun string(column: Int) = cursor.getString(column).orEmpty()
                }
                while (cursor.moveToNext()) row(values)
            }
        }
    }

    /** The database copied out of the assets, again whenever the bundled one differs in size (a newer app). */
    @Synchronized
    private fun copiedOut(path: String): File {
        val file = File(context.noBackupFilesDir, "quran/$path")
        val size = context.assets.openFd("quran/$path").use { it.length }
        if (!file.exists() || file.length() != size) {
            file.parentFile?.mkdirs()
            val temporary = File(file.parentFile, "${file.name}.tmp")
            context.assets.open("quran/$path").use { input -> temporary.outputStream().use { input.copyTo(it) } }
            temporary.renameTo(file)
        }
        return file
    }
}
