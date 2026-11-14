package dev.purepace

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** L1 pure JVM tests for the consent start decision. No Android runtime is started. */
class ConsentContractTest {

    @Test
    fun grantedAllowsStart() {
        val decision = ConsentContract.evaluateStart(granted = true, recording = false)
        assertTrue(decision.allowed)
        assertTrue(decision.recording)
        assertNull(decision.blockedReasonKey)
    }

    @Test
    fun unattendedBlocksStartAndKeepsIdle() {
        val decision = ConsentContract.evaluateStart(granted = false, recording = false)
        assertFalse(decision.allowed)
        assertFalse(decision.recording)
        assertEquals(ConsentContract.KEY_BLOCKED_REASON, decision.blockedReasonKey)
    }

    @Test
    fun grantedMustNotBeBlockedCounterexample() {
        val wrongExpectation = runCatching {
            assertTrue("granted must be blocked", ConsentContract.isStartBlocked(true))
        }
        assertTrue(
            "feeding a granted state with a must-block expectation has to fail",
            wrongExpectation.isFailure,
        )
    }

    @Test
    fun unattendedMustNotBeAllowedCounterexample() {
        val wrongExpectation = runCatching {
            assertFalse("unattended must be allowed", ConsentContract.isStartBlocked(false))
        }
        assertTrue(
            "feeding an unattended state with a must-allow expectation has to fail",
            wrongExpectation.isFailure,
        )
    }

    @Test
    fun missingCopyItemCounterexample() {
        val copy = mutableMapOf<String, String?>(
            ConsentContract.KEY_SENSITIVE to "a",
            ConsentContract.KEY_LOCAL_ONLY to "b",
            ConsentContract.KEY_REFUSABLE to "c",
            ConsentContract.KEY_REVOCABLE to "d",
        )
        assertTrue(ConsentContract.missingCopyItems(copy).isEmpty())

        copy.remove(ConsentContract.KEY_REVOCABLE)
        assertTrue(
            "dropping one key item has to be reported as missing",
            ConsentContract.missingCopyItems(copy).isNotEmpty(),
        )
    }

    @Test
    fun blankCopyCountsAsMissing() {
        val copy = mutableMapOf<String, String?>(
            ConsentContract.KEY_SENSITIVE to "a",
            ConsentContract.KEY_LOCAL_ONLY to " ",
            ConsentContract.KEY_REFUSABLE to "c",
            ConsentContract.KEY_REVOCABLE to "d",
        )
        assertEquals(listOf(ConsentContract.KEY_LOCAL_ONLY), ConsentContract.missingCopyItems(copy))
    }
}
