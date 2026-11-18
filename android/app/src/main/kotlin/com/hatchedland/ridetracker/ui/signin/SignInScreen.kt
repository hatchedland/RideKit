package com.hatchedland.ridetracker.ui.signin

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hatchedland.ridetracker.data.AccountRepository
import com.hatchedland.ridetracker.ui.theme.Brand
import com.hatchedland.ridetracker.ui.theme.MilestoneMark
import kotlinx.coroutines.launch

/** The front door: every feature needs an account. Google or Apple; no email, no password. */
@Composable
fun SignInScreen(account: AccountRepository) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val error by account.error.collectAsStateWithLifecycle()
    val signingIn by account.isSigningIn.collectAsStateWithLifecycle()
    val buttonShape = RoundedCornerShape(16.dp)

    Box(Modifier.fillMaxSize().background(Brand.page())) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            MilestoneMark(width = 56.dp)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Ride Tracker", style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Bold))
                Text(
                    "Record your rides, save the spots you stop at, and ride with friends.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Box(contentAlignment = Alignment.Center) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // Google's button: white, grey outline, near-black text (Google's sign-in branding).
                    OutlinedButton(
                        onClick = { scope.launch { account.signInWithGoogle(context) } },
                        enabled = !signingIn && account.isConfigured,
                        shape = buttonShape,
                        border = BorderStroke(1.dp, Color(0xFF747775)),
                        colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.White, contentColor = Color(0xFF1F1F1F)),
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                    ) { Text("Continue with Google", fontSize = 18.sp, fontWeight = FontWeight.Medium) }

                    // Apple's button: black with white text (white on black in dark mode).
                    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
                    Button(
                        onClick = { scope.launch { account.signInWithApple() } },
                        enabled = !signingIn && account.isConfigured,
                        shape = buttonShape,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (dark) Color.White else Color.Black,
                            contentColor = if (dark) Color.Black else Color.White,
                        ),
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                    ) { Text("Continue with Apple", fontSize = 18.sp, fontWeight = FontWeight.Medium) }
                }
                if (signingIn) CircularProgressIndicator()
            }

            error?.let {
                Text(it, color = Brand.signal(), style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            }

            Text(
                "Your rides, spots and photo details are kept in your account so they're safe on a new phone. " +
                    "Friends only see what you share. Photos stay in your gallery.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun Color.luminance(): Float = 0.2126f * red + 0.7152f * green + 0.0722f * blue
