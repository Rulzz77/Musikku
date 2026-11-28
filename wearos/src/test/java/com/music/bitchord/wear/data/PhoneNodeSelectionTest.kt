package com.music.bitchord.wear.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneNodeSelectionTest {

    @Test
    fun `stale asynchronous connection results cannot replace a newer node`() {
        val firstRequest = 10L
        val secondRequest = 11L
        val currentNode = "phone-b"

        assertFalse(
            isCurrentPhoneSelection(
                currentNode = currentNode,
                requestedNode = "phone-a",
                currentGeneration = secondRequest,
                requestedGeneration = firstRequest,
            ),
        )
        assertTrue(
            isCurrentPhoneSelection(
                currentNode = currentNode,
                requestedNode = "phone-b",
                currentGeneration = secondRequest,
                requestedGeneration = secondRequest,
            ),
        )
        assertFalse(
            isCurrentPhoneSelection(
                currentNode = null,
                requestedNode = "phone-b",
                currentGeneration = secondRequest,
                requestedGeneration = secondRequest,
            ),
        )
    }

    @Test
    fun `only the selected node can publish watch state`() {
        assertTrue(isSelectedPhoneNode("phone-a", "phone-a"))
        assertFalse(isSelectedPhoneNode("phone-a", "phone-b"))
        assertFalse(isSelectedPhoneNode("phone-a", null))
        assertFalse(isSelectedPhoneNode(null, "phone-a"))
        assertFalse(isSelectedPhoneNode(null, null))
        assertFalse(isSelectedPhoneNode("", ""))
    }
}
