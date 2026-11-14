package dev.purepace

import android.content.Context

/** Injectable consent state so pure JVM tests can feed any state. */
interface ConsentStore {
    fun isGranted(): Boolean
    fun setGranted(granted: Boolean)
}

/** Device-local persistence backed by SharedPreferences. */
class SharedPreferencesConsentStore(context: Context) : ConsentStore {
    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override fun isGranted(): Boolean = prefs.getBoolean(KEY_GRANTED, false)

    override fun setGranted(granted: Boolean) {
        prefs.edit().putBoolean(KEY_GRANTED, granted).commit()
    }

    private companion object {
        const val PREFS_NAME = "purepace_consent"
        const val KEY_GRANTED = "granted"
    }
}
