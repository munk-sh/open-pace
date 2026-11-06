package dev.purepace

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * L1 纯 JVM 单测：不启动 Android 运行时，只校验首屏空壳文案契约。
 */
class PlaceholderCopyTest {

    @Test
    fun appNameIsPurePace() {
        assertEquals("PurePace", PlaceholderCopy.APP_NAME)
    }

    @Test
    fun taglineIsNotBlank() {
        assertTrue(PlaceholderCopy.TAGLINE.isNotBlank())
    }

    @Test
    fun tabsAreTheFourPlaceholders() {
        assertEquals(listOf("Run", "History", "Log", "Settings"), PlaceholderCopy.tabs)
    }
}
