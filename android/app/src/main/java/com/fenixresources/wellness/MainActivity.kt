package com.fenixresources.wellness

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.fenixresources.wellness.ui.FenixApp
import com.fenixresources.wellness.ui.FenixTheme

class MainActivity : ComponentActivity() {
    private lateinit var viewModel: MainViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val api = (application as FenixApplication).api
        viewModel = ViewModelProvider(this, object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = MainViewModel(api) as T
        })[MainViewModel::class.java]
        setContent {
            FenixTheme {
                FenixApp(viewModel)
            }
        }
        viewModel.handleDeepLink(intent?.dataString)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        viewModel.handleDeepLink(intent.dataString)
    }
}
