package com.hatchedland.ridetracker.ui.signin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.hatchedland.ridetracker.data.AccountRepository
import com.hatchedland.ridetracker.ui.theme.Brand
import kotlinx.coroutines.launch

/** After the first sign-in: a name for friends and a unique @handle they find you by. */
@Composable
fun HandleSetupScreen(account: AccountRepository) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(account.suggestedName) }
    var handle by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    Column(
        Modifier.fillMaxSize().background(Brand.page()).safeDrawingPadding().imePadding()
            .verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Pick your @handle", style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold))
        Text("Friends find you by it inside the app. Your email is never shown.",
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedTextField(
            value = name, onValueChange = { name = it }, label = { Text("Your name for friends") },
            singleLine = true, modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next),
        )
        OutlinedTextField(
            value = handle, onValueChange = { handle = AccountRepository.normalisedHandle(it) },
            label = { Text("@handle") }, prefix = { Text("@") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            supportingText = { Text("3–20 letters, numbers, _ or .") },
            isError = handle.isNotEmpty() && !AccountRepository.isValidHandle(handle),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Done),
        )
        message?.let { Text(it, color = Brand.signal()) }
        Button(
            onClick = {
                saving = true
                scope.launch { message = account.saveProfile(name, handle); saving = false }
            },
            enabled = !saving && AccountRepository.isValidHandle(handle) && name.isNotBlank(),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Brand.HighwayYellow, contentColor = Brand.Asphalt),
            modifier = Modifier.fillMaxWidth().height(56.dp),
        ) { Text(if (saving) "Saving…" else "Continue", fontWeight = FontWeight.Bold) }
        TextButton(onClick = { scope.launch { account.signOut() } }) { Text("Sign out") }
    }
}
