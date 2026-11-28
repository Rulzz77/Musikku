package com.music.bitchord.wear.data

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.atomic.AtomicLong
import com.music.bitchord.wear.playback.Speaker
import com.music.bitchord.wear.WearProtocol as P

/** True only for a Data Layer event emitted by the selected paired phone. */
internal fun isSelectedPhoneNode(selectedNode: String?, eventHost: String?): Boolean =
    !selectedNode.isNullOrBlank() && eventHost == selectedNode

/** Old connect/cache callbacks must not apply after a newer node selection. */
internal fun isCurrentPhoneSelection(
    currentNode: String?,
    requestedNode: String?,
    currentGeneration: Long,
    requestedGeneration: Long,
): Boolean = currentNode == requestedNode && currentGeneration == requestedGeneration

/**
 * Retain the chosen phone while it is still reachable. When it disappears,
 * use a nearby node first and sort by stable node ID so a reordered capability
 * response cannot silently switch the watch between phones.
 */
internal fun preferredPhoneNode(
    nodes: List<Pair<String, Boolean>>,
    currentNode: String?,
): String? =
    currentNode?.takeIf { current -> nodes.any { it.first == current } }
        ?: nodes.filter { it.second }.minOfOrNull { it.first }
        ?: nodes.minOfOrNull { it.first }

/**
 * The watch's whole view of the phone.
 *
 * Listens only while the app is on screen ([start]/[stop] follow the activity),
 * so a watch app in the background costs nothing: there is no listener service
 * here to be woken by every track change the phone makes.
 *
 * Taps are answered on the watch at once and the phone's word is taken when it
 * arrives. A field the user just changed is held at its new value for a moment,
 * so a state the phone published a few milliseconds *before* the tap reached it
 * can't flick the glyph back.
 */
class PhoneLink(context: Context, private val scope: CoroutineScope) :
    DataClient.OnDataChangedListener,
    CapabilityClient.OnCapabilityChangedListener {

    private val dataClient = Wearable.getDataClient(context)
    private val messageClient = Wearable.getMessageClient(context)
    private val capabilityClient = Wearable.getCapabilityClient(context)

    private val _link = MutableStateFlow(Link.Connecting)
    val link: StateFlow<Link> = _link.asStateFlow()

    private val _nowPlaying = MutableStateFlow<NowPlaying?>(null)
    val nowPlaying: StateFlow<NowPlaying?> = _nowPlaying.asStateFlow()

    /** Whether the phone has said anything at all yet, so "nothing playing" can be told from "not heard". */
    private val _heard = MutableStateFlow(false)
    val heard: StateFlow<Boolean> = _heard.asStateFlow()

    private val _artwork = MutableStateFlow<ImageBitmap?>(null)
    val artwork: StateFlow<ImageBitmap?> = _artwork.asStateFlow()

    private val _volume = MutableStateFlow<Volume?>(null)
    val volume: StateFlow<Volume?> = _volume.asStateFlow()

    private val _queue = MutableStateFlow<Queue?>(null)
    val queue: StateFlow<Queue?> = _queue.asStateFlow()

    /** The phone's outputs, as its own player lists them. Null until asked. */
    private val _outputs = MutableStateFlow<List<PhoneOutput>?>(null)
    val outputs: StateFlow<List<PhoneOutput>?> = _outputs.asStateFlow()

    /**
     * Whether this watch is the phone's speaker. The phone still owns the
     * queue and the state — everything on screen is still the phone's — and
     * [Speaker] only plays what it is told.
     */
    private val _watchSpeaker = MutableStateFlow(false)
    val watchSpeaker: StateFlow<Boolean> = _watchSpeaker.asStateFlow()

    @Volatile private var phoneNode: String? = null
    private val phoneSelectionLock = Any()
    private val phoneSelectionGeneration = AtomicLong()
    private var artId: String? = null
    private var lastNowPlayingAt = 0L
    private val artworkGeneration = AtomicLong()
    private var artJob: Job? = null
    private val queueSnapshotLock = Any()
    private var lastQueueRevision = 0L
    private val queueArtworkGeneration = AtomicLong()
    private var started = false

    private class Hold<T>(val value: T, val until: Long)

    private var holdPlaying: Hold<Boolean>? = null
    private var holdLiked: Hold<Boolean>? = null
    private var holdShuffle: Hold<Boolean>? = null
    private var holdRepeat: Hold<Int>? = null
    private var holdVolumeUntil = 0L

    private val volumeBatchLock = Any()
    private var pendingSteps = 0
    private var volumeJob: Job? = null

    fun start() {
        if (started) return
        started = true
        dataClient.addListener(this)
        capabilityClient.addListener(this, P.CAPABILITY_PHONE)
        scope.launch { connect() }
    }

    fun stop() {
        if (!started) return
        started = false
        dataClient.removeListener(this)
        capabilityClient.removeListener(this, P.CAPABILITY_PHONE)
        phoneSelectionGeneration.incrementAndGet()
    }

    fun retry() {
        _link.value = Link.Connecting
        scope.launch { connect() }
    }

    // ---- Commands, each answered on the watch first ----

    fun togglePlay() {
        val now = System.currentTimeMillis()
        _nowPlaying.update { np ->
            np ?: return@update null
            val playing = !np.playing
            holdPlaying = Hold(playing, now + HOLD_MS)
            if (playing) {
                np.copy(playing = true)
            } else {
                // Freeze the ring where it is rather than let it run on to the
                // phone's answer.
                np.copy(playing = false, advancing = false, positionMs = np.positionAt(now), positionAt = now)
            }
        }
        send(P.CMD_TOGGLE)
    }

    fun next() = send(P.CMD_NEXT)

    fun previous() = send(P.CMD_PREVIOUS)

    fun toggleLike() {
        if (_nowPlaying.value?.canLike != true) return
        _nowPlaying.update { np ->
            np ?: return@update null
            holdLiked = Hold(!np.liked, System.currentTimeMillis() + HOLD_MS)
            np.copy(liked = !np.liked)
        }
        send(P.CMD_LIKE)
    }

    fun toggleShuffle() {
        _nowPlaying.update { np ->
            np ?: return@update null
            holdShuffle = Hold(!np.shuffle, System.currentTimeMillis() + HOLD_MS)
            np.copy(shuffle = !np.shuffle)
        }
        send(P.CMD_SHUFFLE)
    }

    fun cycleRepeat() {
        _nowPlaying.update { np ->
            np ?: return@update null
            // Same cycle as the phone: off -> all -> one -> off.
            val next = when (np.repeatMode) {
                REPEAT_OFF -> REPEAT_ALL
                REPEAT_ALL -> REPEAT_ONE
                else -> REPEAT_OFF
            }
            holdRepeat = Hold(next, System.currentTimeMillis() + HOLD_MS)
            np.copy(repeatMode = next)
        }
        send(P.CMD_REPEAT)
    }

    /** Hold-to-seek's answer. The ring jumps there now; the phone confirms. */
    fun seekTo(positionMs: Long) {
        val now = System.currentTimeMillis()
        _nowPlaying.update { it?.copy(positionMs = positionMs, positionAt = now) }
        send(P.CMD_SEEK, positionMs.toString())
    }

    fun skipTo(index: Int) = send(P.CMD_SKIP_TO, index.toString())

    fun requestQueue() = send(P.CMD_QUEUE)

    /**
     * The crown. Moves the readout at once and sends the steps in small
     * batches, so a fast spin is a handful of messages rather than dozens.
     * The phone turns whichever is the speaker — itself, or this watch.
     */
    fun adjustVolume(steps: Int) {
        if (steps == 0) return
        holdVolumeUntil = System.currentTimeMillis() + VOLUME_HOLD_MS
        _volume.update { v -> v?.copy(level = (v.level + steps).coerceIn(0, v.max)) }
        synchronized(volumeBatchLock) {
            pendingSteps += steps
            if (volumeJob?.isActive == true) return

            volumeJob = scope.launch {
                delay(VOLUME_BATCH_MS)
                while (true) {
                    // More crown movement can arrive while sendMessage is in
                    // flight. Drain again before marking the worker finished,
                    // otherwise those steps sit unsent until the next turn.
                    val batch = synchronized(volumeBatchLock) {
                        if (pendingSteps == 0) {
                            volumeJob = null
                            null
                        } else {
                            pendingSteps.also { pendingSteps = 0 }
                        }
                    } ?: return@launch

                    sendNow(P.CMD_VOLUME, batch.toString())
                }
            }
        }
    }

    // ---- Output: the phone's devices, or this watch ----

    fun requestOutputs() = send(P.CMD_OUTPUTS)

    /** Play through one of the phone's outputs — the phone takes the music back if the watch had it. */
    fun playOnPhone(output: PhoneOutput) {
        _watchSpeaker.value = false
        _outputs.update { list -> list?.map { it.copy(active = it.id == output.id) } }
        send(P.CMD_SELECT_OUTPUT, output.id.toString())
    }

    /** Make this watch the phone's speaker. */
    fun playOnWatch(context: Context) {
        if (_watchSpeaker.value) return
        _watchSpeaker.value = true
        _outputs.update { list -> list?.map { it.copy(active = false) } }
        // Up before the phone's first load arrives, and while the app is on
        // screen, so it is allowed to become a foreground service.
        Speaker.prepare(context)
        send(P.CMD_SPEAKER_WATCH)
    }

    // ---- Data Layer ----

    override fun onDataChanged(events: DataEventBuffer) {
        // Data items are shared at package/signing-identity scope. A watch can
        // see more than one paired phone, so accept only the currently selected
        // node rather than whichever phone happened to publish last.
        val selectedNode = phoneNode ?: return
        // Copy the payload before returning: the DataEventBuffer is released
        // as soon as this callback finishes.
        val changes = events.mapNotNull { event ->
            if (event.type != DataEvent.TYPE_CHANGED) return@mapNotNull null
            val item = event.dataItem
            val host = item.uri.host
            if (!isSelectedPhoneNode(selectedNode, host)) return@mapNotNull null
            Triple(item.uri.path, host, DataMapItem.fromDataItem(item).dataMap)
        }
        changes.forEach { (path, host, map) ->
            synchronized(phoneSelectionLock) {
                // The selected phone may have changed after the event was copied.
                if (!isSelectedPhoneNode(phoneNode, host)) return@synchronized
                _link.value = Link.Connected
                when (path) {
                    P.PATH_NOW_PLAYING -> applyNowPlaying(map)
                    P.PATH_QUEUE -> applyQueue(map)
                    P.PATH_OUTPUTS -> applyOutputs(map)
                }
            }
        }
    }

    override fun onCapabilityChanged(info: CapabilityInfo) {
        val nodeId = preferredPhoneNode(
            info.nodes.map { it.id to it.isNearby },
            currentNode = phoneNode,
        )
        // The capability callback is the ordering point. Select synchronously
        // here, before launching work, so an older queued coroutine cannot
        // overwrite a newer phone selection when scheduling happens out of
        // order. Ignore duplicate notifications while this exact node is
        // already connected or being connected.
        if (nodeId == phoneNode && (_link.value == Link.Connected || _link.value == Link.Connecting)) {
            return
        }
        val generation = selectPhoneNode(nodeId)
        scope.launch { connectTo(nodeId, generation) }
    }

    private fun applyOutputs(map: DataMap) {
        _watchSpeaker.value = map.getBoolean(P.KEY_WATCH_SPEAKER)
        _outputs.value = map.getDataMapArrayList(P.KEY_OUTPUTS).orEmpty().map {
            PhoneOutput(
                id = it.getInt(P.KEY_OUTPUT_ID),
                name = it.getString(P.KEY_OUTPUT_NAME).orEmpty(),
                kind = it.getString(P.KEY_OUTPUT_KIND).orEmpty(),
                active = it.getBoolean(P.KEY_OUTPUT_ACTIVE),
            )
        }
    }

    private suspend fun readCached(nodeId: String) {
        // A host-scoped query is essential here: reading the path without an
        // authority returns all phones' snapshots and can restore the wrong one.
        val uri = Uri.Builder()
            .scheme(PutDataRequest.WEAR_URI_SCHEME)
            .authority(nodeId)
            .path(P.PATH_NOW_PLAYING)
            .build()
        val items = runCatching { dataClient.getDataItems(uri).await() }.getOrNull() ?: return
        try {
            val item = items.firstOrNull {
                it.uri.host == nodeId && it.uri.path == P.PATH_NOW_PLAYING
            } ?: return
            val map = DataMapItem.fromDataItem(item).dataMap
            synchronized(phoneSelectionLock) {
                if (phoneNode == nodeId) {
                    _link.value = Link.Connected
                    applyNowPlaying(map)
                }
            }
        } finally {
            items.release()
        }
    }

    private suspend fun connect() {
        val generationBeforeLookup = phoneSelectionGeneration.get()
        val nodeId = findPhone()
        // A capability event may have selected a newer node while discovery
        // was suspended. Do not let this older lookup take over afterwards.
        val generation = synchronized(phoneSelectionLock) {
            if (phoneSelectionGeneration.get() != generationBeforeLookup) return
            selectPhoneNode(nodeId)
        }
        connectTo(nodeId, generation)
    }

    private suspend fun connectTo(nodeId: String?, generation: Long) {
        synchronized(phoneSelectionLock) {
            if (!isCurrentPhoneSelection(phoneNode, nodeId, phoneSelectionGeneration.get(), generation)) return
        }
        if (nodeId == null) {
            _link.value = Link.NoPhone
            return
        }

        _link.value = Link.Connecting
        val sent = runCatching {
            messageClient.sendMessage(nodeId, "${P.PATH_COMMAND}/${P.CMD_SYNC}", ByteArray(0)).await()
        }.isSuccess

        synchronized(phoneSelectionLock) {
            if (!isCurrentPhoneSelection(phoneNode, nodeId, phoneSelectionGeneration.get(), generation)) return
            if (sent) _link.value = Link.Connected else _link.value = Link.NoPhone
        }
        if (sent) readCached(nodeId)
    }

    /**
     * Selects the source of truth for the watch. Switching phones invalidates
     * async artwork, queue revisions, optimistic holds, and cached screen data
     * so no state from the previous phone can leak into the new session.
     */
    private fun selectPhoneNode(nodeId: String?): Long = synchronized(phoneSelectionLock) {
        if (phoneNode != nodeId) {
            phoneNode = nodeId
            artJob?.cancel()
            artJob = null
            artId = null
            lastNowPlayingAt = 0L
            artworkGeneration.incrementAndGet()
            _artwork.value = null
            _queue.value = null
            _nowPlaying.value = null
            _volume.value = null
            _outputs.value = null
            _watchSpeaker.value = false
            _heard.value = false
            holdPlaying = null
            holdLiked = null
            holdShuffle = null
            holdRepeat = null
            synchronized(volumeBatchLock) {
                volumeJob?.cancel()
                volumeJob = null
                pendingSteps = 0
            }
            holdVolumeUntil = 0L
            synchronized(queueSnapshotLock) {
                lastQueueRevision = 0L
                queueArtworkGeneration.incrementAndGet()
            }
        }
        _link.value = if (nodeId == null) Link.NoPhone else Link.Connecting
        phoneSelectionGeneration.incrementAndGet()
    }

    private suspend fun findPhone(): String? = withTimeoutOrNull(FIND_TIMEOUT_MS) {
        runCatching {
            val info = capabilityClient.getCapability(P.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE).await()
            preferredPhoneNode(info.nodes.map { it.id to it.isNearby }, currentNode = phoneNode)
        }.getOrNull()
    }

    private fun send(command: String, arg: String = "") {
        scope.launch { sendNow(command, arg) }
    }

    private suspend fun sendNow(command: String, arg: String = ""): Boolean {
        repeat(2) { attempt ->
            val node = phoneNode ?: findPhone()?.also { selectPhoneNode(it) }
            if (node == null) {
                _link.value = Link.NoPhone
                return false
            }
            val sent = runCatching {
                messageClient.sendMessage(node, "${P.PATH_COMMAND}/$command", arg.toByteArray()).await()
            }.onFailure { Log.w(TAG, "send $command (attempt $attempt): ${it.message}") }.isSuccess
            if (sent) {
                val stillSelected = synchronized(phoneSelectionLock) {
                    if (phoneNode == node) {
                        _link.value = Link.Connected
                        true
                    } else {
                        false
                    }
                }
                if (stillSelected) return true
            }
            // The node may have changed (phone rebooted, re-paired): look again once.
            if (phoneNode == node) selectPhoneNode(null)
        }
        _link.value = Link.NoPhone
        return false
    }

    private fun applyNowPlaying(map: DataMap) {
        // Data Layer callbacks and the initial cached read can race. Preserve
        // the newest player snapshot even when an older event arrives late.
        val positionAt = map.getLong(P.KEY_POSITION_AT, 0L)
        if (positionAt > 0L && positionAt < lastNowPlayingAt) return
        if (positionAt > 0L) lastNowPlayingAt = positionAt
        _heard.value = true
        _watchSpeaker.value = map.getBoolean(P.KEY_WATCH_SPEAKER)
        val now = System.currentTimeMillis()
        _nowPlaying.value = NowPlaying.from(map)?.let { merge(it, now) }

        if (now >= holdVolumeUntil && map.containsKey(P.KEY_VOLUME)) {
            _volume.value = Volume(map.getInt(P.KEY_VOLUME), map.getInt(P.KEY_VOLUME_MAX))
        }

        val id = map.getString(P.KEY_ART_ID)
        if (id == artId) return
        artId = id
        val generation = artworkGeneration.incrementAndGet()
        artJob?.cancel()
        val asset = map.getAsset(P.KEY_ART)
        if (asset == null) {
            _artwork.value = null
            return
        }
        artJob = scope.launch {
            val bitmap = decode(asset)
            if (artworkGeneration.get() == generation) _artwork.value = bitmap
        }
    }

    private fun merge(incoming: NowPlaying, now: Long): NowPlaying {
        fun <T> Hold<T>?.resolve(actual: T, clear: () -> Unit): T = when {
            this == null -> actual
            now > until || value == actual -> { clear(); actual }
            else -> value
        }
        return incoming.copy(
            playing = holdPlaying.resolve(incoming.playing) { holdPlaying = null },
            liked = holdLiked.resolve(incoming.liked) { holdLiked = null },
            shuffle = holdShuffle.resolve(incoming.shuffle) { holdShuffle = null },
            repeatMode = holdRepeat.resolve(incoming.repeatMode) { holdRepeat = null },
        )
    }

    private fun applyQueue(map: DataMap) {
        val revision = map.getLong(P.KEY_QUEUE_REVISION, 0L)
        val items = map.getDataMapArrayList(P.KEY_ITEMS).orEmpty()
        val current = map.getInt(P.KEY_CURRENT_INDEX)
        val mediaId = map.getString(P.KEY_QUEUE_MEDIA_ID).orEmpty()
        val rows = items.map {
            QueueRow(
                index = it.getInt(P.KEY_INDEX),
                title = it.getString(P.KEY_TITLE).orEmpty(),
                artist = it.getString(P.KEY_ARTIST).orEmpty(),
                art = null,
            )
        }

        // Revision validation, generation assignment, and the visible text
        // update are one atomic step. Listener callbacks can be concurrent;
        // otherwise an older callback could pass its check, pause, and publish
        // its rows after a newer callback had already advanced the queue.
        val generation = synchronized(queueSnapshotLock) {
            if ((revision == 0L && lastQueueRevision > 0L) ||
                (revision > 0L && revision < lastQueueRevision)
            ) return
            if (revision > 0L) lastQueueRevision = revision
            queueArtworkGeneration.incrementAndGet().also {
                _queue.value = Queue(rows, current, mediaId)
            }
        }
        // Thumbnails after the text, in one go, so the list is readable at once
        // and recomposes once more rather than once per row.
        scope.launch {
            val art = items.map { item ->
                async { item.getAsset(P.KEY_ART)?.let { decode(it) } }
            }.awaitAll()
            if (queueArtworkGeneration.get() != generation) return@launch
            _queue.update { q ->
                if (q == null || q.mediaId != mediaId || queueArtworkGeneration.get() != generation) q
                else q.copy(rows = q.rows.mapIndexed { i, row -> row.copy(art = art.getOrNull(i)) })
            }
        }
    }

    private suspend fun decode(asset: Asset): ImageBitmap? = withContext(Dispatchers.IO) {
        runCatching {
            dataClient.getFdForAsset(asset).await().inputStream.use { stream ->
                BitmapFactory.decodeStream(stream)?.also { it.prepareToDraw() }?.asImageBitmap()
            }
        }.getOrNull()
    }

    companion object {
        private const val TAG = "MusikKuWear"
        private const val HOLD_MS = 2_500L
        private const val VOLUME_HOLD_MS = 1_500L
        private const val VOLUME_BATCH_MS = 90L
        private const val FIND_TIMEOUT_MS = 6_000L

        const val REPEAT_OFF = 0
        const val REPEAT_ONE = 1
        const val REPEAT_ALL = 2
    }
}
