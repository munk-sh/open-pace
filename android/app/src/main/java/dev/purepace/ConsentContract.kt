package dev.purepace

/**
 * Single source of truth for the consent gate contract.
 *
 * UI tags, string resource keys and the start decision live here so Compose code and
 * tests share one definition. User visible copy is always resolved from resources.
 */
object ConsentContract {
    const val CONSENT_ROOT_TAG = "consent.root"
    const val BLOCKED_REASON_TAG = "consent.blockedReason"
    const val AGREE_TAG = "consent.agree"
    const val DECLINE_TAG = "consent.decline"
    const val START_ATTEMPT_TAG = "consent.startAttempt"
    const val ABOUT_ENTRY_TAG = "about.entry"
    const val ABOUT_ROOT_TAG = "about.root"
    const val WITHDRAW_TAG = "about.withdraw"
    const val WITHDRAW_CONFIRM_TAG = "about.withdrawConfirm"
    const val RUN_START_TAG = "run.start"
    const val RUN_RECORDING_TAG = "run.recording"
    const val POLICY_TEXT_TAG = "policy.text"

    const val KEY_TITLE = "consent_title"
    const val KEY_SENSITIVE = "consent_body_sensitive"
    const val KEY_LOCAL_ONLY = "consent_body_local"
    const val KEY_REFUSABLE = "consent_body_refuse"
    const val KEY_REVOCABLE = "consent_body_withdraw"
    const val KEY_AGREE = "consent_agree"
    const val KEY_DECLINE = "consent_decline"
    const val KEY_BLOCKED_REASON = "consent_blocked_reason"
    const val KEY_ROLE_PRIMARY = "consent_role_primary"
    const val KEY_ROLE_SECONDARY = "consent_role_secondary"

    val fourKeyItems: List<String> = listOf(
        KEY_SENSITIVE,
        KEY_LOCAL_ONLY,
        KEY_REFUSABLE,
        KEY_REVOCABLE,
    )

    data class StartDecision(
        val allowed: Boolean,
        val recording: Boolean,
        val blockedReasonKey: String?,
    )

    /** A start is allowed only after the consent was granted explicitly. */
    fun evaluateStart(granted: Boolean, recording: Boolean): StartDecision =
        if (granted) {
            StartDecision(allowed = true, recording = true, blockedReasonKey = null)
        } else {
            StartDecision(allowed = false, recording = recording, blockedReasonKey = KEY_BLOCKED_REASON)
        }

    fun isStartBlocked(granted: Boolean): Boolean = !granted

    /** Empty only when every required copy item resolved to non-blank text. */
    fun missingCopyItems(copy: Map<String, String?>): List<String> =
        fourKeyItems.filter { key -> copy[key].isNullOrBlank() }
}
