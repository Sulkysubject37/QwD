package com.qwd.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qwd.app.ui.theme.LabProColorScheme
import com.qwd.app.ui.theme.StandardColorScheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class UIFlavor { LabPro, ClearInsight }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen() {
    var flavor by remember { mutableStateOf(UIFlavor.LabPro) }
    var selectedFileUri by remember { mutableStateOf<String?>(null) }
    var isAnalyzing by remember { mutableStateOf(false) }
    var resultJson by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri -> selectedFileUri = uri?.toString() }

    val colorScheme = if (flavor == UIFlavor.LabPro) LabProColorScheme else StandardColorScheme

    MaterialTheme(colorScheme = colorScheme) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { 
                        Text(
                            if (flavor == UIFlavor.LabPro) "QwD // LAB-NATIVE" else "QwD Clear Insight",
                            fontWeight = FontWeight.Black,
                            fontFamily = FontFamily.Monospace
                        ) 
                    },
                    actions = {
                        IconButton(onClick = { 
                            flavor = if (flavor == UIFlavor.LabPro) UIFlavor.ClearInsight else UIFlavor.LabPro 
                        }) {
                            Icon(Icons.Filled.Settings, contentDescription = "Switch Flavor")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                        titleContentColor = MaterialTheme.colorScheme.primary
                    )
                )
            },
            floatingActionButton = {
                if (selectedFileUri != null && !isAnalyzing) {
                    ExtendedFloatingActionButton(
                        onClick = {
                            scope.launch {
                                isAnalyzing = true
                                delay(1500)
                                resultJson = mockDetailedResult()
                                isAnalyzing = false
                            }
                        },
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                        icon = { Icon(Icons.Filled.PlayArrow, null) },
                        text = { Text("START RUN") }
                    )
                }
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.surface)
                    .padding(16.dp)
            ) {
                // File Section
                OutlinedCard(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(4.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            if (selectedFileUri == null) "NO SOURCE LOADED" else "SOURCE: ${selectedFileUri?.takeLast(20)}",
                            fontFamily = FontFamily.Monospace,
                            fontSize = 12.sp
                        )
                        Spacer(modifier = Modifier.weight(1f))
                        TextButton(onClick = { filePickerLauncher.launch("*/*") }) {
                            Text("SELECT")
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                if (isAnalyzing) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                            Text("STREAMING SIMD ENGINE...", modifier = Modifier.padding(8.dp), fontFamily = FontFamily.Monospace)
                        }
                    }
                } else if (resultJson != null) {
                    ResultDashboard(flavor)
                }
            }
        }
    }
}

@Composable
fun ResultDashboard(flavor: UIFlavor) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                MetricCard(
                    label = if (flavor == UIFlavor.LabPro) "TOTAL_READS" else "Read Count",
                    value = "10.0M",
                    modifier = Modifier.weight(1f),
                    flavor = flavor
                )
                MetricCard(
                    label = if (flavor == UIFlavor.LabPro) "DUPLICATION" else "Redundancy",
                    value = "1.57%",
                    modifier = Modifier.weight(1f),
                    flavor = flavor,
                    isWarning = true
                )
            }
        }

        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        if (flavor == UIFlavor.LabPro) "GC_DISTRIBUTION" else "Chemical Balance",
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    DistributionChart(
                        data = listOf(10, 20, 45, 80, 100, 70, 30, 10),
                        color = MaterialTheme.colorScheme.primary
                    )
                    if (flavor == UIFlavor.ClearInsight) {
                        Text(
                            "Insight: The GC content is balanced, matching typical human genomic data.",
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                }
            }
        }

        item {
            if (flavor == UIFlavor.ClearInsight) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
                ) {
                    Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Info, null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Data Confidence is high. No artifacts detected.", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
fun MetricCard(label: String, value: String, modifier: Modifier, flavor: UIFlavor, isWarning: Boolean = false) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(
            containerColor = if (isWarning && flavor == UIFlavor.ClearInsight) Color(0xFFFFEBEE) else MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(label, fontSize = 10.sp, color = MaterialTheme.colorScheme.secondary, fontFamily = FontFamily.Monospace)
            Text(value, fontSize = 24.sp, fontWeight = FontWeight.Black, color = if (isWarning && flavor == UIFlavor.ClearInsight) Color.Red else MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
fun DistributionChart(data: List<Int>, color: Color) {
    Canvas(modifier = Modifier.fillMaxWidth().height(100.dp)) {
        val width = size.width
        val height = size.height
        val maxVal = data.maxOrNull() ?: 1
        val step = width / (data.size - 1)

        val path = Path().apply {
            moveTo(0f, height - (data[0].toFloat() / maxVal * height))
            data.forEachIndexed { index, value ->
                if (index > 0) {
                    lineTo(index * step, height - (value.toFloat() / maxVal * height))
                }
            }
        }

        drawPath(path = path, color = color, style = Stroke(width = 3.dp.toPx()))
        // Fill area under path
        path.lineTo(width, height)
        path.lineTo(0f, height)
        path.close()
        drawPath(path = path, color = color.copy(alpha = 0.1f))
    }
}

fun mockDetailedResult(): String {
    return "{ \"status\": \"success\" }"
}
