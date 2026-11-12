package com.music.bitchord.data.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteConfigParserTest {

    @Test
    fun validConfigReadsRevisionAndFeatureFlags() {
        val parsed = parseRemoteConfig(
            """
            {
              "schemaVersion": 1,
              "revision": 4,
              "features": {
                "globalSearch": false,
                "playlistSearch": true
              }
            }
            """.trimIndent(),
        )

        assertNotNull(parsed)
        assertEquals(4, parsed?.revision)
        assertFalse(parsed!!.features.globalSearch)
        assertTrue(parsed.features.playlistSearch)
    }

    @Test
    fun missingFeatureFlagsKeepFeaturesEnabled() {
        val parsed = parseRemoteConfig(
            """
            {
              "schemaVersion": 1,
              "revision": 1,
              "features": {}
            }
            """.trimIndent(),
        )

        assertNotNull(parsed)
        assertTrue(parsed!!.features.globalSearch)
        assertTrue(parsed.features.playlistSearch)
    }

    @Test
    fun unknownSchemaVersionIsRejected() {
        val parsed = parseRemoteConfig(
            """
            {
              "schemaVersion": 2,
              "revision": 2,
              "features": {}
            }
            """.trimIndent(),
        )

        assertNull(parsed)
    }

    @Test
    fun malformedOrIncompleteJsonIsRejected() {
        assertNull(parseRemoteConfig("{"))
        assertNull(parseRemoteConfig("""{"schemaVersion":1,"revision":1}"""))
        assertNull(parseRemoteConfig("""{"schemaVersion":1,"revision":0,"features":{}}"""))
    }

    @Test
    fun invalidFlagValueFallsBackToEnabled() {
        val parsed = parseRemoteConfig(
            """
            {
              "schemaVersion": 1,
              "revision": 3,
              "features": {
                "globalSearch": "disabled",
                "playlistSearch": false
              }
            }
            """.trimIndent(),
        )

        assertNotNull(parsed)
        assertTrue(parsed!!.features.globalSearch)
        assertFalse(parsed.features.playlistSearch)
    }
}
