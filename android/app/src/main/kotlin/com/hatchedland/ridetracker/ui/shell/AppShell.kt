package com.hatchedland.ridetracker.ui.shell

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hatchedland.ridetracker.data.AccountRepository
import com.hatchedland.ridetracker.ui.theme.Brand
import kotlinx.coroutines.launch

/** The five tabs, as on iOS. Hidden while riding (comes with the recording slice). */
enum class Tab(val title: String, val icon: ImageVector) {
    Ride("Ride", Icons.Filled.PlayArrow),
    Spots("Spots", Icons.Filled.Place),
    Rides("Rides", Icons.AutoMirrored.Filled.List),
    Friends("Friends", Icons.Filled.Person),
    Settings("Settings", Icons.Filled.Settings),
}

@Composable
fun AppShell(account: AccountRepository) {
    var tab by rememberSaveable { mutableTabState() }
    Scaffold(
        containerColor = Brand.page(),
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach {
                    NavigationBarItem(
                        selected = tab == it,
                        onClick = { tab = it },
                        icon = { Icon(it.icon, contentDescription = null) },
                        label = { Text(it.title) },
                    )
                }
            }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(tab.title, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold))
            when (tab) {
                Tab.Settings -> SettingsPlaceholder(account)
                // Phase 1 fills these in: Room + sync, then recording, then spots and rides.
                else -> Text("Coming in the next Android build.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun SettingsPlaceholder(account: AccountRepository) {
    val scope = rememberCoroutineScope()
    val state by account.state.collectAsStateWithLifecycle()
    (state as? AccountRepository.State.SignedIn)?.email?.takeIf { it.isNotEmpty() }?.let {
        Text("Signed in as $it", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    TextButton(onClick = { scope.launch { account.signOut() } }) { Text("Sign out", color = Brand.signal()) }
}

private fun mutableTabState() = androidx.compose.runtime.mutableStateOf(Tab.Ride)
