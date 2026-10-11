package com.azzamalrashed.aqra.recitation

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Getting the model onto the device: a download that stops carries on from where it was, the archive is checked
 * against its checksum, and only a whole model counts as installed. The files are stand-ins; nothing is downloaded.
 */
class RecitationModelTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val version = "whisper-test-1"
    private val modelFiles = mapOf(
        "encoder.onnx" to ByteArray(3_000) { (it % 251).toByte() },
        "decoder.onnx" to ByteArray(5_000) { (it % 241).toByte() },
        "mel_filters.bin" to ByteArray(640) { (it % 7).toByte() },
        "tokens.txt" to "a\nb\nc\n".toByteArray(),
    )

    private fun zipOf(files: Map<String, ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            for ((name, bytes) in files) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return out.toByteArray()
    }

    private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun files(checksum: String, size: Long, installedSize: Long = 0) =
        RecitationModelFiles(File(temp.root, "recitation"), File(temp.root, "cache"), version, checksum, size, installedSize)

    /**
     * A server holding [bytes], answering ranges. With [failAfter], the connection drops after that many bytes of the
     * first request.
     */
    private class Server(private val bytes: ByteArray, private var failAfter: Int? = null) : RecitationModelFiles.Fetcher {
        val requests = ArrayList<Long>()

        override fun open(from: Long): RecitationModelFiles.Response {
            requests += from
            if (from >= bytes.size) return RecitationModelFiles.Response(416, 0, "bytes */${bytes.size}", ByteArrayInputStream(ByteArray(0)))
            val rest = bytes.copyOfRange(from.toInt(), bytes.size)
            val stream: InputStream = failAfter?.let { limit -> failAfter = null; Dropping(rest, limit) } ?: ByteArrayInputStream(rest)
            return if (from > 0) {
                RecitationModelFiles.Response(206, rest.size.toLong(), "bytes $from-${bytes.size - 1}/${bytes.size}", stream)
            } else {
                RecitationModelFiles.Response(200, rest.size.toLong(), null, stream)
            }
        }

        private class Dropping(private val bytes: ByteArray, private val limit: Int) : InputStream() {
            private var at = 0
            override fun read(): Int = throw UnsupportedOperationException()
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (at >= limit) throw IOException("the connection dropped")
                val count = minOf(len, limit - at, bytes.size - at)
                System.arraycopy(bytes, at, b, off, count)
                at += count
                return count
            }
        }
    }

    @Test
    fun aChecksumMismatchIsNotInstalled() {
        val zip = zipOf(modelFiles)
        val files = files(checksum = "0".repeat(64), size = zip.size.toLong())
        files.download(Server(zip))
        assertTrue(files.archive.exists())
        val problem = assertThrows(RecitationModelFiles.Problem::class.java) { files.install() }
        assertEquals(RecitationModel.Failure.CORRUPT, problem.failure)
        assertFalse(files.isInstalled)
        assertFalse(files.folder.exists())
        // The archive is thrown away, so the next try downloads it afresh rather than failing the same way.
        assertFalse(files.archive.exists())
    }

    @Test
    fun aMatchingArchiveIsInstalledAndTheArchiveRemoved() {
        val zip = zipOf(modelFiles)
        val files = files(checksum = sha256(zip), size = zip.size.toLong())
        val progress = ArrayList<Double>()
        files.download(Server(zip)) { progress += it }
        files.install()
        assertTrue(files.isInstalled)
        assertEquals(modelFiles.keys, files.folder.list()!!.toSet())
        assertFalse(files.archive.exists())
        assertFalse(File(files.folder.parentFile, "$version.partial").exists())
    }

    @Test
    fun anEmptyArchiveIsNotInstalled() {
        for (zip in listOf(zipOf(emptyMap()), zipOf(mapOf("tokens.txt" to "a\n".toByteArray(), "encoder.onnx" to ByteArray(0))))) {
            val files = files(checksum = sha256(zip), size = zip.size.toLong())
            files.download(Server(zip))
            val problem = assertThrows(RecitationModelFiles.Problem::class.java) { files.install() }
            assertEquals(RecitationModel.Failure.CORRUPT, problem.failure)
            assertFalse(files.isInstalled)
            assertFalse(files.folder.exists())
        }
    }

    @Test
    fun aDownloadResumesWhereItStopped() {
        val zip = zipOf(modelFiles)
        val server = Server(zip, failAfter = 1_000)
        val files = files(checksum = sha256(zip), size = zip.size.toLong())
        assertThrows(IOException::class.java) { files.download(server) }
        assertEquals(1_000L, files.archive.length())
        assertEquals(1_000.0 / zip.size, files.fractionDownloaded(), 1e-9)
        files.download(server)
        assertEquals(listOf(0L, 1_000L), server.requests)
        assertEquals(zip.size.toLong(), files.archive.length())
        files.install()
        assertTrue(files.isInstalled)
    }

    @Test
    fun aWholeArchiveIsntDownloadedAgain() {
        val zip = zipOf(modelFiles)
        val server = Server(zip)
        val files = files(checksum = sha256(zip), size = zip.size.toLong())
        files.download(server)
        files.download(server)
        assertEquals(listOf(0L), server.requests)
        files.install()
        assertTrue(files.isInstalled)
    }

    @Test
    fun oldVersionsAndLeftoversAreCleanedUp() {
        val files = files(checksum = "", size = 1)
        val root = File(temp.root, "recitation")
        val cache = File(temp.root, "cache")
        val old = File(root, "whisper-old-0").apply { mkdirs(); File(this, "encoder.onnx").writeText("x") }
        val partial = File(root, "$version.partial").apply { mkdirs() }
        val current = File(root, version).apply { mkdirs(); File(this, "tokens.txt").writeText("a") }
        cache.mkdirs()
        val oldArchive = File(cache, "recitation-whisper-old-0.zip").apply { writeText("x") }
        val ourArchive = File(cache, "recitation-$version.zip").apply { writeText("x") }
        val someoneElses = File(cache, "pages.zip").apply { writeText("x") }
        files.cleanUp()
        assertFalse(old.exists())
        assertFalse(partial.exists())
        assertFalse(oldArchive.exists())
        assertTrue(current.exists())
        assertTrue(ourArchive.exists())
        assertTrue(someoneElses.exists())
    }

    @Test
    fun aDownloadNeedsRoomForTheArchiveAndTheModel() {
        val files = files(checksum = "", size = 1, installedSize = Long.MAX_VALUE / 4)
        val problem = assertThrows(RecitationModelFiles.Problem::class.java) { files.requireFreeSpace() }
        assertEquals(RecitationModel.Failure.SPACE, problem.failure)
        files(checksum = "", size = 1, installedSize = 0).requireFreeSpace()
    }

    @Test
    fun theChecksumIsSha256() {
        val file = temp.newFile().apply { writeText("abc") }
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", RecitationModelFiles.sha256(file))
        assertEquals(RecitationModel.CHECKSUM.length, 64)
    }
}
