package dev.purepace

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Robolectric driven Compose tests for the consent gate. No emulator is required. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ConsentGateScreenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private fun newStore() = SharedPreferencesConsentStore(RuntimeEnvironment.getApplication())

    private fun bodyCopy(): Map<String, String> {
        val context = RuntimeEnvironment.getApplication()
        return mapOf(
            ConsentContract.KEY_SENSITIVE to context.getString(R.string.consent_body_sensitive),
            ConsentContract.KEY_LOCAL_ONLY to context.getString(R.string.consent_body_local),
            ConsentContract.KEY_REFUSABLE to context.getString(R.string.consent_body_refuse),
            ConsentContract.KEY_REVOCABLE to context.getString(R.string.consent_body_withdraw),
        )
    }

    @Test
    fun firstLaunchShowsConsentGateAsRoot() {
        composeRule.setContent { PurePaceApp(store = newStore()) }

        composeRule.onNodeWithTag(ConsentContract.CONSENT_ROOT_TAG).assertIsDisplayed()
        composeRule.onNodeWithTag(ConsentContract.RUN_START_TAG).assertDoesNotExist()

        val context = RuntimeEnvironment.getApplication()
        listOf(
            R.string.consent_body_sensitive,
            R.string.consent_body_local,
            R.string.consent_body_refuse,
            R.string.consent_body_withdraw,
        ).forEach { id ->
            val text = context.getString(id)
            assertTrue(text.isNotBlank())
            composeRule.onNodeWithText(text, substring = true).assertExists()
        }

        val joined = bodyCopy().values.joinToString(" ")
        assertTrue(joined.contains("敏感个人信息"))
        assertTrue(joined.contains("只存在本机"))
        assertTrue(joined.contains("可以拒绝"))
        assertTrue(joined.contains("可随时撤回"))
        assertEquals(emptyList<String>(), ConsentContract.missingCopyItems(bodyCopy()))
    }

    @Test
    fun unattendedStartAttemptStaysBlockedWithReason() {
        val store = newStore()
        composeRule.setContent { PurePaceApp(store = store) }

        composeRule.onNodeWithTag(ConsentContract.START_ATTEMPT_TAG).performClick()

        composeRule.onNodeWithTag(ConsentContract.CONSENT_ROOT_TAG).assertExists()
        composeRule.onNodeWithTag(ConsentContract.BLOCKED_REASON_TAG).assertIsDisplayed()
        val reason = RuntimeEnvironment.getApplication().getString(R.string.consent_blocked_reason)
        assertTrue(reason.isNotBlank())
        composeRule.onNodeWithTag(ConsentContract.BLOCKED_REASON_TAG).assertTextEquals(reason)
        composeRule.onNodeWithTag(ConsentContract.RUN_START_TAG).assertDoesNotExist()
        assertFalse(store.isGranted())
    }

    @Test
    fun agreeGrantsAndEnablesStart() {
        val store = newStore()
        composeRule.setContent { PurePaceApp(store = store) }

        composeRule.onNodeWithTag(ConsentContract.AGREE_TAG).performClick()

        composeRule.onNodeWithTag(ConsentContract.CONSENT_ROOT_TAG).assertDoesNotExist()
        composeRule.onNodeWithTag(ConsentContract.RUN_START_TAG).assertExists().assertIsEnabled()
        assertTrue(store.isGranted())
        assertTrue(newStore().isGranted())

        composeRule.onNodeWithTag(ConsentContract.RUN_START_TAG).performClick()
        composeRule.onNodeWithTag(ConsentContract.RUN_RECORDING_TAG).assertExists()
        composeRule.onNodeWithTag(ConsentContract.RUN_START_TAG).assertIsNotEnabled()
    }

    @Test
    fun declineStaysUnattended() {
        val store = newStore()
        composeRule.setContent { PurePaceApp(store = store) }

        composeRule.onNodeWithTag(ConsentContract.DECLINE_TAG).performClick()

        composeRule.onNodeWithTag(ConsentContract.CONSENT_ROOT_TAG).assertExists()
        composeRule.onNodeWithTag(ConsentContract.BLOCKED_REASON_TAG).assertExists()
        assertFalse(store.isGranted())
        assertFalse(newStore().isGranted())
    }

    @Test
    fun withdrawReturnsUnattended() {
        val store = newStore()
        store.setGranted(true)
        composeRule.setContent { PurePaceApp(store = store) }

        composeRule.onNodeWithTag(ConsentContract.ABOUT_ENTRY_TAG).performClick()
        composeRule.onNodeWithTag(ConsentContract.ABOUT_ROOT_TAG).assertExists()

        val paragraphs = RuntimeEnvironment.getApplication()
            .resources
            .getStringArray(R.array.privacy_policy_paragraphs)
        assertTrue(paragraphs.size >= 4)
        paragraphs.forEach { paragraph ->
            composeRule.onNodeWithText(paragraph, substring = true).assertExists()
        }

        composeRule.onNodeWithTag(ConsentContract.WITHDRAW_TAG).performClick()
        composeRule.onNodeWithTag(ConsentContract.WITHDRAW_CONFIRM_TAG).performClick()

        composeRule.onNodeWithTag(ConsentContract.CONSENT_ROOT_TAG).assertExists()
        composeRule.onNodeWithTag(ConsentContract.BLOCKED_REASON_TAG).assertExists()
        composeRule.onNodeWithTag(ConsentContract.RUN_START_TAG).assertDoesNotExist()
        assertFalse(store.isGranted())
        assertFalse(newStore().isGranted())
    }

    @Test
    fun primaryAndSecondaryActionsHaveDistinctRoles() {
        composeRule.setContent { PurePaceApp(store = newStore()) }
        val context = RuntimeEnvironment.getApplication()

        composeRule.onNodeWithTag(ConsentContract.AGREE_TAG).assertExists()
        composeRule.onNodeWithTag(ConsentContract.DECLINE_TAG).assertExists()

        val primary = composeRule.onNodeWithTag(ConsentContract.AGREE_TAG)
            .fetchSemanticsNode()
            .config[SemanticsProperties.StateDescription]
        val secondary = composeRule.onNodeWithTag(ConsentContract.DECLINE_TAG)
            .fetchSemanticsNode()
            .config[SemanticsProperties.StateDescription]

        assertEquals(context.getString(R.string.consent_role_primary), primary)
        assertEquals(context.getString(R.string.consent_role_secondary), secondary)
        assertTrue(primary != secondary)
    }
}
