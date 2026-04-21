package com.qwd.app.ui.theme

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color

// Cruel / Obsidian Palette
val Obsidian = Color(0xFF0F0F0F)
val PhosphorGreen = Color(0xFF00FF41)
val DimGreen = Color(0xFF003B00)

// Bone / Ink Palette
val Bone = Color(0xFFF5F5F5)
val Ink = Color(0xFF1A1A1B)
val ArchiveGray = Color(0xFF8E8E93)

val LabProColorScheme = darkColorScheme(
    primary = PhosphorGreen,
    onPrimary = Color.Black,
    surface = Obsidian,
    onSurface = PhosphorGreen,
    secondary = ArchiveGray
)

val StandardColorScheme = lightColorScheme(
    primary = Ink,
    onPrimary = Color.White,
    surface = Bone,
    onSurface = Ink,
    secondary = ArchiveGray
)
