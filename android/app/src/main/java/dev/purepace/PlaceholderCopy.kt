package dev.purepace

/**
 * 首屏空壳文案与 Tab 占位结构的单一来源。
 * 本阶段不承载任何业务数据或样例记录。
 */
object PlaceholderCopy {
    const val APP_NAME: String = "PurePace"
    const val TAGLINE: String = "A quiet running timer and calorie log."
    val tabs: List<String> = listOf("Run", "History", "Log", "Settings")
}
