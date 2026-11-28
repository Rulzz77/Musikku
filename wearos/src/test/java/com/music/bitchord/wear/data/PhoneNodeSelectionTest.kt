package com.music.bitchord.wear.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneNodeSelectionTest {

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
