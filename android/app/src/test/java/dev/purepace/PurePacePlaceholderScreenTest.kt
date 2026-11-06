package dev.purepace

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Robolectric 驱动的 Compose UI 测试：零模拟器，随 testDebugUnitTest 执行。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PurePacePlaceholderScreenTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun firstScreenShowsNameTaglineAndTabPlaceholders() {
        composeRule.setContent { PurePacePlaceholder() }

        composeRule.onNodeWithText(PlaceholderCopy.APP_NAME).assertIsDisplayed()
        composeRule.onNodeWithText(PlaceholderCopy.TAGLINE).assertIsDisplayed()
        PlaceholderCopy.tabs.forEach { label ->
            composeRule.onNodeWithText(label).assertIsDisplayed()
        }
    }
}
