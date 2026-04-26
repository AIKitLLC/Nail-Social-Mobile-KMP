package com.nailtryon.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.nailtryon.android.ui.NailBrowserScreen
import com.nailtryon.android.ui.NailTryOnScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    NailTryOnApp()
                }
            }
        }
    }
}

sealed class Screen(val route: String) {
    object Browser : Screen("browser")
    object TryOn : Screen("try_on/{designId}") {
        fun createRoute(designId: String) = "try_on/$designId"
    }
}

@Composable
fun NailTryOnApp() {
    val context = androidx.compose.ui.platform.LocalContext.current
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED
        )
    }

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
        if (!granted) {
            Toast.makeText(context, "Camera permission is required", Toast.LENGTH_LONG).show()
        }
    }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) {
            launcher.launch(Manifest.permission.CAMERA)
        }
    }

    if (hasCameraPermission) {
        val navController = rememberNavController()
        NavHost(navController = navController, startDestination = Screen.Browser.route) {
            composable(Screen.Browser.route) {
                NailBrowserScreen(
                    onDesignSelected = { designId ->
                        navController.navigate(Screen.TryOn.createRoute(designId))
                    }
                )
            }
            composable(Screen.TryOn.route) { backStackEntry ->
                val designId = backStackEntry.arguments?.getString("designId")
                NailTryOnScreen(designId = designId)
            }
        }
    }
}
