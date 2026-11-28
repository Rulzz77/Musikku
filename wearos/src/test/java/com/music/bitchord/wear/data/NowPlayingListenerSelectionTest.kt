package com.music.bitchord.wear.data

import com.music.bitchord.wear.WearProtocol as P
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NowPlayingListenerSelectionTest {

    @Test
    fun `only selected phone may update ongoing activity`() {
        assertTrue(isSelectedNowPlayingEvent("phone-a", "phone-a", P.PATH_NOW_PLAYING))
        assertFalse(isSelectedNowPlayingEvent("phone-a", "phone-b", P.PATH_NOW_PLAYING))
        assertFalse(isSelectedNowPlayingEvent("phone-a", null, P.PATH_NOW_PLAYING))
        assertFalse(isSelectedNowPlayingEvent(null, "phone-a", P.PATH_NOW_PLAYING))
        assertFalse(isSelectedNowPlayingEvent("phone-a", "phone-a", P.PATH_QUEUE))
        assertFalse(isSelectedNowPlayingEvent(null, null, null))
    }
}
