package com.hatchedland.ridetracker

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hatchedland.ridetracker.data.AccountRepository
import com.hatchedland.ridetracker.ui.shell.AppShell
import com.hatchedland.ridetracker.ui.signin.HandleSetupScreen
import com.hatchedland.ridetracker.ui.signin.SignInScreen
import com.hatchedland.ridetracker.ui.theme.Brand
import com.hatchedland.ridetracker.ui.theme.RideTrackerTheme
import io.github.jan.supabase.auth.handleDeeplinks

class MainActivity : ComponentActivity() {
    private val app get() = application as RideTrackerApp

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        handleAuthCallback(intent)
        setContent { RideTrackerTheme { Root(app.account) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAuthCallback(intent)
    }

    /** Sign in with Apple returns as ridetracker://auth-callback… from the Custom Tab. */
    private fun handleAuthCallback(intent: Intent?) {
        if (intent?.data?.scheme == "ridetracker") app.supabase?.handleDeeplinks(intent)
    }
}

/** Signed out, only sign-in shows; signed in without a @handle, only the handle step. */
@Composable
private fun Root(account: AccountRepository) {
    val state by account.state.collectAsStateWithLifecycle()
    val needsHandle by account.needsHandle.collectAsStateWithLifecycle()
    when (state) {
        // Reading the saved session: a plain page, not a sign-in flash.
        AccountRepository.State.Checking -> Box(Modifier.fillMaxSize().background(Brand.page()))
        AccountRepository.State.SignedOut -> SignInScreen(account)
        is AccountRepository.State.SignedIn -> if (needsHandle) HandleSetupScreen(account) else AppShell(account)
    }
}
