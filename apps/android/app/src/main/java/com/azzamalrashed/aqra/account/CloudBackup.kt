package com.azzamalrashed.aqra.account

import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.core.decodeLossy
import com.azzamalrashed.aqra.memorization.AyahMemory
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionStore
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlin.math.abs

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
 *   since 1970 (rows written before the plan have only the first five). An ayah unmarked on a device leaves a
 *   tombstone in its place, `[removedAt, 0, -1, 0, 0, -1, -1]`: no app reads a row with a stability of 0 as
 *   memorized, and the merge won't bring the ayah back from a copy that still holds it;
 * - `users/{uid}/revision/state`: the revision store's [RevisionStore.Snapshot], as JSON, beside `revisedDays` and
 *   `completedDays` as arrays that are only ever added to, so a streak day one device wrote survives another's
 *   write of the JSON;
 * - `users/{uid}/journey/state`: the plan, rewards and assessments ([Journey.Snapshot]), as JSON.
 *
 * A device writes only the rows that changed since it last read the account, merged into each block, so two devices
 * writing different ayat of one block don't overwrite each other (see [CloudSync]).
 */
object CloudBackup {
    const val BLOCK_SIZE = 256
    val BLOCK_COUNT = (MushafStore.AYAH_COUNT + BLOCK_SIZE - 1) / BLOCK_SIZE

    fun blockId(index: Int): String = "block-" + (if (index < 10) "0" else "") + index

    /**
     * What a device knows of the memorization: the ayat memorized, and those unmarked and when, kept so a merge
     * doesn't bring an unmarked ayah back from a copy that still holds it.
     */
    data class Memory(val ayahs: Map<Int, AyahMemory> = emptyMap(), val removed: Map<Int, Moment> = emptyMap()) {
        companion object {
            val EMPTY = Memory()
        }
    }

    // MARK: - Ayat

    /** Seconds since 1970 beyond which a number can't be a date this app wrote: it's a corrupt row. */
    private const val FARTHEST_DATE = 1e12

    fun encode(memory: AyahMemory): List<Double> = listOf(
        memory.since.epochSeconds, memory.stability, memory.lastReviewed?.epochSeconds ?: -1.0,
        memory.lapses.toDouble(), if (memory.verified) 1.0 else 0.0, memory.learnedAt?.epochSeconds ?: -1.0,
        memory.lastLapseAt?.epochSeconds ?: -1.0,
    )

    /** The row left where an ayah was unmarked. */
    fun tombstone(removedAt: Moment): List<Double> = listOf(removedAt.epochSeconds, 0.0, -1.0, 0.0, 0.0, -1.0, -1.0)

    /**
     * A memorized ayah from its row; null for a tombstone, a row too short to read, or one with numbers no app could
     * have written (not finite, or far outside any date).
     */
    fun decode(row: List<Double>): AyahMemory? {
        if (row.size < 5 || row.any { !it.isFinite() } || row[1] <= 0 || row[1] > 1e6) return null
        if (abs(row[0]) >= FARTHEST_DATE || abs(row[2]) >= FARTHEST_DATE || abs(row[3]) >= 1e9) return null
        if (row.size >= 7 && (abs(row[5]) >= FARTHEST_DATE || abs(row[6]) >= FARTHEST_DATE)) return null
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

    /** When an ayah was unmarked, from its tombstone; null for any other row. */
    fun removedAt(row: List<Double>): Moment? {
        if (row.size < 2 || !row[0].isFinite() || row[1] != 0.0 || abs(row[0]) >= FARTHEST_DATE) return null
        return Moment.ofEpochSeconds(row[0])
    }

    /** How many numbers of a row this app reads; a newer app may add more after them. */
    private const val ROW_SIZE = 7

    /** Every block, by its index, empty where nothing is memorized or unmarked. */
    fun blocks(memory: Memory): Map<Int, BackupBlock> {
        val blocks = (0 until BLOCK_COUNT).associateWith { HashMap<String, List<Double>>() }
        for ((ayah, removedAt) in memory.removed) {
            if (ayah !in 0 until MushafStore.AYAH_COUNT) continue
            blocks.getValue(ayah / BLOCK_SIZE)[ayah.toString()] = tombstone(removedAt)
        }
        for ((ayah, record) in memory.ayahs) {
            if (ayah !in 0 until MushafStore.AYAH_COUNT) continue
            blocks.getValue(ayah / BLOCK_SIZE)[ayah.toString()] = encode(record)
        }
        return blocks
    }

    fun blocks(ayahs: Map<Int, AyahMemory>): Map<Int, BackupBlock> = blocks(Memory(ayahs))

    /** The ayat held in some blocks, and the tombstones; rows that can't be read are skipped. */
    fun memory(blocks: Iterable<BackupBlock>): Memory {
        val ayahs = HashMap<Int, AyahMemory>()
        val removed = HashMap<Int, Moment>()
        for (block in blocks) {
            for ((key, row) in block) {
                val ayah = key.toIntOrNull() ?: continue
                if (ayah !in 0 until MushafStore.AYAH_COUNT) continue
                val record = decode(row)
                if (record != null) ayahs[ayah] = record else removedAt(row)?.let { removed[ayah] = it }
            }
        }
        return Memory(ayahs, removed)
    }

    fun ayahs(blocks: Iterable<BackupBlock>): Map<Int, AyahMemory> = memory(blocks).ayahs

    // MARK: - Merging

    /**
     * Two records of one ayah as one. The record revised later wins (one never revised ranks lowest; a tie goes to
     * the one known longer, then the firmer); the memorization is kept from its earliest date on either side, as is
     * when it was learned; every stumble counts; and a teacher's confirmation holds unless the other copy stumbled on
     * the ayah after it.
     */
    fun merge(a: AyahMemory, b: AyahMemory): AyahMemory {
        val aReviewed = a.lastReviewed ?: Moment.DISTANT_PAST
        val bReviewed = b.lastReviewed ?: Moment.DISTANT_PAST
        val aWins = when {
            aReviewed != bReviewed -> aReviewed > bReviewed
            a.since != b.since -> a.since < b.since
            else -> a.stability >= b.stability
        }
        val (winner, loser) = if (aWins) a to b else b to a
        fun stillVerified(side: AyahMemory, other: AyahMemory): Boolean {
            if (!side.verified) return false
            val stumble = other.lastLapseAt ?: return true
            return stumble <= (side.lastReviewed ?: side.since)
        }
        return winner.copy(
            since = minOf(a.since, b.since),
            learnedAt = listOfNotNull(a.learnedAt, b.learnedAt).minOrNull(),
            lapses = maxOf(a.lapses, b.lapses),
            lastLapseAt = listOfNotNull(a.lastLapseAt, b.lastLapseAt).maxOrNull(),
            verified = stillVerified(winner, loser) || stillVerified(loser, winner),
        )
    }

    /**
     * The ayat memorized on either side, each merged by [merge]; an ayah unmarked on one side after the other last
     * touched it stays unmarked, and one marked again after it was unmarked comes back.
     */
    fun merge(local: Memory, remote: Memory): Memory {
        val ayahs = HashMap<Int, AyahMemory>()
        val removed = HashMap<Int, Moment>()
        val keys = local.ayahs.keys + remote.ayahs.keys + local.removed.keys + remote.removed.keys
        for (ayah in keys) {
            val sides = listOfNotNull(local.ayahs[ayah], remote.ayahs[ayah])
            val record = if (sides.size == 2) merge(sides[0], sides[1]) else sides.firstOrNull()
            val removedAt = listOfNotNull(local.removed[ayah], remote.removed[ayah]).maxOrNull()
            when {
                record != null && removedAt != null && removedAt > sides.maxOf(::lastTouch) -> removed[ayah] = removedAt
                record != null -> ayahs[ayah] = record
                removedAt != null -> removed[ayah] = removedAt
            }
        }
        return Memory(ayahs, removed)
    }

    fun merge(local: Map<Int, AyahMemory>, remote: Map<Int, AyahMemory>): Map<Int, AyahMemory> =
        merge(Memory(local), Memory(remote)).ayahs

    /** The last moment anything happened to a record: it was marked, learned, revised or stumbled on. */
    private fun lastTouch(memory: AyahMemory): Moment =
        listOfNotNull(memory.since, memory.lastReviewed, memory.learnedAt, memory.lastLapseAt).max()

    /**
     * Both revision records as one:
     * - the rotation's place and today's plan come from the side that revised most recently, since they follow the
     *   revising (a device just cleared or newly installed has none to offer); a page of that plan done on the other
     *   side counts as done;
     * - the follow-ups are those of both sides, page by page, each at its later due date;
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
        val other = if (revisedLast) local else remote
        val (newer, older) = if (remote.updatedAt >= local.updatedAt) remote to local else local to remote
        val followUps = HashMap(local.followUps)
        for ((page, theirs) in remote.followUps) {
            val mine = followUps[page]
            followUps[page] = if (mine != null && mine.due >= theirs.due) mine else theirs
        }
        var plan = merged.plan
        val otherPlan = other.plan
        if (plan != null && otherPlan != null && plan.day == otherPlan.day) {
            val doneElsewhere = otherPlan.items.filter { it.done }.map { it.page }.toSet()
            plan = plan.copy(items = plan.items.map { if (it.page in doneElsewhere) it.copy(done = true) else it })
        }
        val seen = HashSet<RevisionRecord>()
        return merged.copy(
            dailyPages = newer.dailyPages ?: older.dailyPages,
            followUps = followUps,
            plan = plan,
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

    /** [blocks], with each memorized row's extra numbers put back. */
    fun blocks(memory: Memory, extras: Map<Int, List<Double>>): Map<Int, BackupBlock> {
        if (extras.isEmpty()) return blocks(memory)
        return blocks(memory).mapValues { (_, block) ->
            block.mapValues { (key, row) -> if (key.toInt() in memory.ayahs) extras[key.toInt()]?.let { row + it } ?: row else row }
        }
    }

    fun blocks(ayahs: Map<Int, AyahMemory>, extras: Map<Int, List<Double>>): Map<Int, BackupBlock> = blocks(Memory(ayahs), extras)

    /**
     * The account's record, as this app or the iOS app wrote it, or a newer version of either: a key missing or
     * unknown never fails it, and an entry of its lists that can't be read is skipped rather than losing the rest.
     */
    fun decodeRevision(json: String): RevisionStore.Snapshot? =
        ProgressJson.decodeLossy(RevisionStore.Snapshot.serializer(), json, listOf("history", "plan.items"))
}
