package dev.purepace

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

private enum class AppScreen { CONSENT, HOME, ABOUT }

@Composable
fun PurePaceApp(store: ConsentStore, modifier: Modifier = Modifier) {
    var granted by remember { mutableStateOf(store.isGranted()) }
    var screen by remember { mutableStateOf(if (granted) AppScreen.HOME else AppScreen.CONSENT) }
    var blockedReasonVisible by remember { mutableStateOf(false) }
    var recording by remember { mutableStateOf(false) }

    MaterialTheme {
        Surface(modifier = modifier.fillMaxSize()) {
            when (screen) {
                AppScreen.CONSENT -> ConsentScreen(
                    blockedReasonVisible = blockedReasonVisible,
                    onAgree = {
                        store.setGranted(true)
                        granted = true
                        recording = false
                        blockedReasonVisible = false
                        screen = AppScreen.HOME
                    },
                    onDecline = { blockedReasonVisible = true },
                    onStartAttempt = {
                        val decision = ConsentContract.evaluateStart(granted, recording)
                        if (decision.allowed) {
                            recording = true
                        } else {
                            blockedReasonVisible = true
                        }
                    },
                )

                AppScreen.HOME -> HomeScreen(
                    recording = recording,
                    onStart = {
                        val decision = ConsentContract.evaluateStart(granted, recording)
                        if (decision.allowed) {
                            recording = true
                        }
                    },
                    onOpenAbout = { screen = AppScreen.ABOUT },
                )

                AppScreen.ABOUT -> AboutScreen(
                    onBack = { screen = AppScreen.HOME },
                    onWithdraw = {
                        store.setGranted(false)
                        granted = false
                        recording = false
                        blockedReasonVisible = true
                        screen = AppScreen.CONSENT
                    },
                )
            }
        }
    }
}

@Composable
private fun ConsentScreen(
    blockedReasonVisible: Boolean,
    onAgree: () -> Unit,
    onDecline: () -> Unit,
    onStartAttempt: () -> Unit,
) {
    val primaryRole = stringResource(R.string.consent_role_primary)
    val secondaryRole = stringResource(R.string.consent_role_secondary)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp)
            .testTag(ConsentContract.CONSENT_ROOT_TAG),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = stringResource(R.string.consent_title),
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.consent_body_sensitive),
            style = MaterialTheme.typography.bodyLarge,
        )
        Text(
            text = stringResource(R.string.consent_body_local),
            style = MaterialTheme.typography.bodyLarge,
        )
        Text(
            text = stringResource(R.string.consent_body_refuse),
            style = MaterialTheme.typography.bodyLarge,
        )
        Text(
            text = stringResource(R.string.consent_body_withdraw),
            style = MaterialTheme.typography.bodyLarge,
        )
        if (blockedReasonVisible) {
            Text(
                text = stringResource(R.string.consent_blocked_reason),
                modifier = Modifier.testTag(ConsentContract.BLOCKED_REASON_TAG),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Button(
            onClick = onStartAttempt,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(ConsentContract.START_ATTEMPT_TAG),
        ) {
            Text(text = stringResource(R.string.main_start_record))
        }
        Button(
            onClick = onAgree,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(ConsentContract.AGREE_TAG)
                .semantics { stateDescription = primaryRole },
        ) {
            Text(text = stringResource(R.string.consent_agree))
        }
        TextButton(
            onClick = onDecline,
            modifier = Modifier
                .fillMaxWidth()
                .testTag(ConsentContract.DECLINE_TAG)
                .semantics { stateDescription = secondaryRole },
        ) {
            Text(text = stringResource(R.string.consent_decline))
        }
    }
}

@Composable
private fun HomeScreen(
    recording: Boolean,
    onStart: () -> Unit,
    onOpenAbout: () -> Unit,
) {
    Box(modifier = Modifier.fillMaxSize()) {
        PurePacePlaceholder()
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (recording) {
                Text(
                    text = stringResource(R.string.main_record_active),
                    modifier = Modifier.testTag(ConsentContract.RUN_RECORDING_TAG),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            Button(
                onClick = onStart,
                enabled = !recording,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(ConsentContract.RUN_START_TAG),
            ) {
                Text(text = stringResource(R.string.main_start_record))
            }
            TextButton(
                onClick = onOpenAbout,
                modifier = Modifier.testTag(ConsentContract.ABOUT_ENTRY_TAG),
            ) {
                Text(text = stringResource(R.string.about_entry))
            }
        }
    }
}

@Composable
private fun AboutScreen(
    onBack: () -> Unit,
    onWithdraw: () -> Unit,
) {
    var confirmingWithdraw by remember { mutableStateOf(false) }
    val paragraphs = stringArrayResource(R.array.privacy_policy_paragraphs)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp)
            .testTag(ConsentContract.ABOUT_ROOT_TAG),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = stringResource(R.string.about_title),
            style = MaterialTheme.typography.headlineSmall,
        )
        Text(
            text = stringResource(R.string.about_policy_section),
            style = MaterialTheme.typography.titleMedium,
        )
        TextButton(
            onClick = { confirmingWithdraw = true },
            modifier = Modifier.testTag(ConsentContract.WITHDRAW_TAG),
        ) {
            Text(text = stringResource(R.string.about_withdraw))
        }
        if (confirmingWithdraw) {
            Text(
                text = stringResource(R.string.about_withdraw_confirm_title),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = stringResource(R.string.about_withdraw_confirm_message),
                style = MaterialTheme.typography.bodyMedium,
            )
            Button(
                onClick = {
                    confirmingWithdraw = false
                    onWithdraw()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(ConsentContract.WITHDRAW_CONFIRM_TAG),
            ) {
                Text(text = stringResource(R.string.about_withdraw_confirm))
            }
            TextButton(onClick = { confirmingWithdraw = false }) {
                Text(text = stringResource(R.string.about_withdraw_cancel))
            }
        }
        TextButton(onClick = onBack) {
            Text(text = stringResource(R.string.back))
        }
        Text(
            text = stringResource(R.string.policy_title),
            style = MaterialTheme.typography.titleMedium,
        )
        paragraphs.forEach { paragraph ->
            Text(
                text = paragraph,
                modifier = Modifier.testTag(ConsentContract.POLICY_TEXT_TAG),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}
