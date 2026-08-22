package com.fenixresources.wellness.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val colors = darkColorScheme(
    primary = Color(0xFFFF9D1C), secondary = Color(0xFFFFC066),
    background = Color(0xFF071B34), surface = Color(0xFF102946), onPrimary = Color(0xFF071B34)
)

@Composable fun FenixTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = colors, content = content)
