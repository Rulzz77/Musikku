package com.music.bitchord.wear.data

import org.junit.Assert.assertEquals
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
    fun `keeps the current reachable phone regardless of capability ordering`() {
        val firstOrder = listOf("phone-b" to true, "phone-a" to true)
        val reversedOrder = firstOrder.reversed()

        assertEquals("phone-a", preferredPhoneNode(firstOrder, "phone-a"))
        assertEquals("phone-a", preferredPhoneNode(reversedOrder, "phone-a"))
    }

    @Test
    fun `chooses a nearby phone deterministically when the current phone disappears`() {
        assertEquals(
            "phone-a",
            preferredPhoneNode(
                listOf("phone-z" to false, "phone-b" to true, "phone-a" to true),
                currentNode = "phone-removed",
            ),
        )
        assertEquals(
            "phone-a",
            preferredPhoneNode(
                listOf("phone-z" to false, "phone-a" to false),
                currentNode = null,
            ),
        )
        assertEquals(null, preferredPhoneNode(emptyList(), currentNode = null))
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
