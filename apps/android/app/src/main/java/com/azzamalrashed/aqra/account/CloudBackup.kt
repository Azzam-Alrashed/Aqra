package com.azzamalrashed.aqra.account

import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.memorization.AyahMemory
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionStore
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/** One block of the backup: each memorized ayah, by its number, as a row of numbers. */
typealias BackupBlock = Map<String, List<Double>>

/**
 * How the student's progress is laid out in the account, and how a device's copy and the account's are merged.
 * Plain values only, with no Firebase, so every rule can be tested. The iOS app uses the same layout and rules, so
 * a student can move between the two.
 *
 * The account holds:
 * - `users/{uid}/memory/block-NN`: the memorized ayat in blocks of 256, each ayah as
 *   `[since, stability, lastReviewed or -1, lapses, verified, learnedAt or -1, lastLapseAt or -1]`, dates in seconds
 *   since 1970 (rows written before the plan have only the first five);
 * - `users/{uid}/revision/state`: the revision store's [RevisionStore.Snapshot], as JSON;
 * - `users/{uid}/journey/state`: the plan, rewards and assessments ([Journey.Snapshot]), as JSON.
 */
object CloudBackup {
    const val BLOCK_SIZE = 256
    val BLOCK_COUNT = (MushafStore.AYAH_COUNT + BLOCK_SIZE - 1) / BLOCK_SIZE

    fun blockId(index: Int): String = "block-" + (if (index < 10) "0" else "") + index

    // MARK: - Ayat

    fun encode(memory: AyahMemory): List<Double> = listOf(
        memory.since.epochSeconds, memory.stability, memory.lastReviewed?.epochSeconds ?: -1.0,
        memory.lapses.toDouble(), if (memory.verified) 1.0 else 0.0, memory.learnedAt?.epochSeconds ?: -1.0,
        memory.lastLapseAt?.epochSeconds ?: -1.0,
    )

    fun decode(row: List<Double>): AyahMemory? {
        if (row.size < 5 || row[1] <= 0) return null
        return AyahMemory(
            since = Moment.ofEpochSeconds(row[0]),
            stability = row[1],
            lastReviewed = if (row[2] < 0) null else Moment.ofEpochSeconds(row[2]),
            lapses = maxOf(row[3].toInt(), 0),
            verified = row[4] != 0.0,
            learnedAt = if (row.size >= 7 && row[5] >= 0) Moment.ofEpochSeconds(row[5]) else null,
            lastLapseAt = if (row.size >= 7 && row[6] >= 0) Moment.ofEpochSeconds(row[6]) else null,
        )
    }

    /** How many numbers of a row this app reads; a newer app may add more after them. */
    private const val ROW_SIZE = 7

    /** Every block, by its index, empty where nothing is memorized. */
    fun blocks(ayahs: Map<Int, AyahMemory>): Map<Int, BackupBlock> {
        val blocks = (0 until BLOCK_COUNT).associateWith { HashMap<String, List<Double>>() }
        for ((ayah, memory) in ayahs) {
            if (ayah !in 0 until MushafStore.AYAH_COUNT) continue
            blocks.getValue(ayah / BLOCK_SIZE)[ayah.toString()] = encode(memory)
        }
        return blocks
    }

    /** The ayat held in some blocks; rows that can't be read are skipped. */
    fun ayahs(blocks: Iterable<BackupBlock>): Map<Int, AyahMemory> {
        val ayahs = HashMap<Int, AyahMemory>()
        for (block in blocks) {
            for ((key, row) in block) {
                val ayah = key.toIntOrNull() ?: continue
                if (ayah !in 0 until MushafStore.AYAH_COUNT) continue
                ayahs[ayah] = decode(row) ?: continue
            }
        }
        return ayahs
    }

    // MARK: - Merging

    /**
     * The ayat memorized on either side. Where both have an ayah, the one revised more recently wins, and a teacher's
     * confirmation on either side is kept.
     */
    fun merge(local: Map<Int, AyahMemory>, remote: Map<Int, AyahMemory>): Map<Int, AyahMemory> {
        val merged = HashMap(local)
        for ((ayah, theirs) in remote) {
            val mine = local[ayah]
            if (mine == null) {
                merged[ayah] = theirs
                continue
            }
            val newer = if ((theirs.lastReviewed ?: theirs.since) > (mine.lastReviewed ?: mine.since)) theirs else mine
            merged[ayah] = newer.copy(verified = mine.verified || theirs.verified)
        }
        return merged
    }

    /**
     * Both revision records as one:
     * - the rotation's place, the follow-ups and today's plan come from the side that revised most recently, since
     *   they follow the revising (a device just cleared or newly installed has none to offer);
     * - the daily amount is the most recent choice made on either side;
     * - the days revised and the history are those of both.
     * Ties go to the account's copy.
     */
    fun merge(local: RevisionStore.Snapshot, remote: RevisionStore.Snapshot): RevisionStore.Snapshot {
        fun lastRevision(snapshot: RevisionStore.Snapshot): Moment = maxOf(
            snapshot.history.maxOfOrNull { it.date } ?: Moment.DISTANT_PAST,
            snapshot.revisedDays.maxOrNull() ?: Moment.DISTANT_PAST,
        )
        val localRevised = lastRevision(local)
        val remoteRevised = lastRevision(remote)
        val revisedLast = remoteRevised > localRevised || (remoteRevised == localRevised && remote.updatedAt >= local.updatedAt)
        val merged = if (revisedLast) remote else local
        val (newer, older) = if (remote.updatedAt >= local.updatedAt) remote to local else local to remote
        val seen = HashSet<RevisionRecord>()
        return merged.copy(
            dailyPages = newer.dailyPages ?: older.dailyPages,
            revisedDays = (local.revisedDays + remote.revisedDays).toSortedSet().toList(),
            completedDays = (local.completedDays.orEmpty() + remote.completedDays.orEmpty()).toSortedSet().toList().ifEmpty { null },
            history = (local.history + remote.history).sortedBy { it.date }.filter { seen.add(it) }.takeLast(1_000),
            updatedAt = maxOf(local.updatedAt, remote.updatedAt),
        )
    }

    // MARK: - The revision record

    /**
     * The record as JSON. [carrying] holds fields a newer app (on iOS or here) wrote into the account that this one
     * doesn't know: they're written back as they came, so a student moving between devices loses nothing.
     */
    fun encode(snapshot: RevisionStore.Snapshot, carrying: JsonObject = JsonObject(emptyMap())): String {
        val known = ProgressJson.encodeToJsonElement(RevisionStore.Snapshot.serializer(), snapshot).jsonObject
        return JsonObject(carrying.filterKeys { it !in known } + known).toString()
    }

    /** The fields of a revision record this app doesn't know, to carry back when it writes the record again. */
    fun unknownFields(json: String): JsonObject {
        val all = runCatching { ProgressJson.parseToJsonElement(json).jsonObject }.getOrNull() ?: return JsonObject(emptyMap())
        val known = RevisionStore.Snapshot.serializer().descriptor.let { d -> (0 until d.elementsCount).map(d::getElementName).toSet() }
        return JsonObject(all.filterKeys { it !in known })
    }

    /**
     * The numbers of an ayah's row past the seven this app reads (a newer app may add more), to carry back when the
     * row is written again.
     */
    fun extraValues(blocks: Iterable<BackupBlock>): Map<Int, List<Double>> = buildMap {
        for (block in blocks) for ((key, row) in block) {
            val ayah = key.toIntOrNull() ?: continue
            if (row.size > ROW_SIZE) put(ayah, row.drop(ROW_SIZE))
        }
    }

    /** [blocks], with each row's extra numbers put back. */
    fun blocks(ayahs: Map<Int, AyahMemory>, extras: Map<Int, List<Double>>): Map<Int, BackupBlock> {
        if (extras.isEmpty()) return blocks(ayahs)
        return blocks(ayahs).mapValues { (_, block) ->
            block.mapValues { (key, row) -> extras[key.toInt()]?.let { row + it } ?: row }
        }
    }

    fun decodeRevision(json: String): RevisionStore.Snapshot? =
        runCatching { ProgressJson.decodeFromString(RevisionStore.Snapshot.serializer(), json) }.getOrNull()
}
