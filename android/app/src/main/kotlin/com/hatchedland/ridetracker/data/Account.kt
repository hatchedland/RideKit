package com.hatchedland.ridetracker.data

import android.content.Context
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.hatchedland.ridetracker.BuildConfig
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.ExternalAuthAction
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Apple
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.storage.Storage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.IOException
import java.security.MessageDigest
import java.security.SecureRandom

/** The Supabase project (same as iOS); `null` when this build has no secrets.properties values. */
fun makeSupabase(): SupabaseClient? {
    val projectHost = BuildConfig.SUPABASE_HOST
    val key = BuildConfig.SUPABASE_PUBLISHABLE_KEY
    if (projectHost.isBlank() || key.isBlank() || projectHost.contains("YOUR_")) return null
    return createSupabaseClient("https://$projectHost", key) {
        install(Auth) {
            scheme = "ridetracker"
            host = "auth-callback"
            defaultExternalAuthAction = ExternalAuthAction.CustomTabs()
        }
        install(Postgrest)
        install(Storage)
        install(Functions)
    }
}

/**
 * The rider's account. Required: signed out, the app shows only sign-in (CLAUDE.md "Accounts").
 * Sign in with Google (Credential Manager → ID token) or Apple (Supabase OAuth in a Custom Tab).
 * No email or password. The same verified email is the same account on iOS and Android.
 */
class AccountRepository(private val supabase: SupabaseClient?, scope: CoroutineScope) {

    sealed interface State {
        /** Reading the saved session at launch. */
        data object Checking : State
        data object SignedOut : State
        /** Apple may hide the address; display only. */
        data class SignedIn(val userID: String, val email: String) : State
    }

    @Serializable
    data class Profile(val username: String? = null, @SerialName("display_name") val displayName: String = "")

    private val profile = MutableStateFlow<Profile?>(null)
    private val _error = MutableStateFlow<String?>(null)
    private val _signingIn = MutableStateFlow(false)
    val error: StateFlow<String?> = _error.asStateFlow()
    val isSigningIn: StateFlow<Boolean> = _signingIn.asStateFlow()
    val isConfigured: Boolean get() = supabase != null

    val state: StateFlow<State> = (supabase?.auth?.sessionStatus ?: MutableStateFlow(SessionStatus.NotAuthenticated(false)))
        .let { status ->
            combine(status, profile) { s, _ ->
                when (s) {
                    is SessionStatus.Initializing -> State.Checking
                    is SessionStatus.Authenticated -> s.session.user?.let { State.SignedIn(it.id, it.email ?: "") } ?: State.Checking
                    // A refresh that failed offline keeps the rider signed in; the SDK retries.
                    is SessionStatus.RefreshFailure -> supabase?.auth?.currentUserOrNull()?.let { State.SignedIn(it.id, it.email ?: "") } ?: State.SignedOut
                    is SessionStatus.NotAuthenticated -> State.SignedOut
                }
            }
        }
        .stateIn(scope, SharingStarted.Eagerly, State.Checking)

    /** Signed in but no @handle yet: the app asks for one before anything else. */
    val needsHandle: StateFlow<Boolean> = combine(state, profile) { s, p ->
        s is State.SignedIn && p != null && p.username.isNullOrEmpty()
    }.stateIn(scope, SharingStarted.Eagerly, false)

    init {
        scope.launch {
            state.collect { if (it is State.SignedIn && profile.value == null) loadProfile() else if (it is State.SignedOut) profile.value = null }
        }
    }

    // MARK: Sign in

    /** Google through Credential Manager; Supabase checks the ID token against the hashed nonce. */
    suspend fun signInWithGoogle(activityContext: Context) {
        val client = supabase ?: return run { _error.value = "Accounts aren't set up in this build." }
        val webClientID = BuildConfig.GOOGLE_WEB_CLIENT_ID
        if (webClientID.isBlank()) return run { _error.value = "Google sign-in isn't set up in this build." }
        if (_signingIn.value) return
        _signingIn.value = true
        _error.value = null
        try {
            val nonce = randomNonce()
            val option = GetGoogleIdOption.Builder()
                .setServerClientId(webClientID)
                .setFilterByAuthorizedAccounts(false)
                .setNonce(sha256(nonce))
                .build()
            val result = CredentialManager.create(activityContext)
                .getCredential(activityContext, GetCredentialRequest.Builder().addCredentialOption(option).build())
            val credential = result.credential
            if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                _error.value = "Google sign-in didn't work. Try again."
                return
            }
            val google = GoogleIdTokenCredential.createFrom(credential.data)
            client.auth.signInWith(IDToken) {
                idToken = google.idToken
                provider = Google
                this.nonce = nonce
            }
            // Google shares the name; it fills the name field of the @handle step.
            google.displayName?.takeIf { it.isNotBlank() }?.let { suggestedName = it }
        } catch (_: GetCredentialCancellationException) {
            // The rider closed the sheet.
        } catch (_: NoCredentialException) {
            _error.value = "Add a Google account to this phone, or sign in with Apple."
        } catch (e: IOException) {
            _error.value = NO_CONNECTION
        } catch (e: Exception) {
            Log.e(TAG, "Google sign-in failed", e)
            _error.value = "Couldn't sign in. Try again."
        } finally {
            _signingIn.value = false
        }
    }

    /** Apple through Supabase's OAuth flow in a Custom Tab; it comes back via ridetracker://auth-callback. */
    suspend fun signInWithApple() {
        val client = supabase ?: return run { _error.value = "Accounts aren't set up in this build." }
        _error.value = null
        try {
            client.auth.signInWith(Apple)
        } catch (e: IOException) {
            _error.value = NO_CONNECTION
        } catch (e: Exception) {
            Log.e(TAG, "Apple sign-in failed", e)
            _error.value = "Sign in with Apple didn't work. Try again."
        }
    }

    suspend fun signOut() {
        runCatching { supabase?.auth?.signOut() }
        profile.value = null
    }

    // MARK: Profile and @handle

    /** A name to prefill the @handle step with (from Google). */
    var suggestedName: String = ""
        private set

    suspend fun loadProfile() {
        val client = supabase ?: return
        val id = client.auth.currentUserOrNull()?.id ?: return
        profile.value = runCatching {
            client.from("profiles").select(Columns.list("username", "display_name")) { filter { eq("id", id) } }
                .decodeSingle<Profile>()
        }.onFailure { Log.w(TAG, "Profile didn't load", it) }.getOrNull()
        profile.value?.displayName?.takeIf { it.isNotBlank() }?.let { suggestedName = it }
    }

    /** Saves name and @handle. Returns a message for the rider if it didn't work. */
    suspend fun saveProfile(name: String, handleInput: String): String? {
        val handle = normalisedHandle(handleInput)
        if (!isValidHandle(handle)) return "Use 3–20 letters, numbers, _ or ."
        val trimmedName = name.trim()
        if (trimmedName.isEmpty()) return "Add your name, so friends know it's you."
        val client = supabase ?: return "You're signed out."
        val id = client.auth.currentUserOrNull()?.id ?: return "You're signed out."
        return try {
            client.from("profiles").update({
                set("username", handle)
                set("display_name", trimmedName.take(60))
            }) { filter { eq("id", id) } }
            profile.value = Profile(handle, trimmedName)
            null
        } catch (e: IOException) {
            NO_CONNECTION
        } catch (e: Exception) {
            val text = e.message.orEmpty().lowercase()
            if ("duplicate" in text || "unique" in text || "23505" in text) "@$handle is taken. Try another." else "Couldn't save. Try again."
        }
    }

    companion object {
        private const val TAG = "Account"
        private const val NO_CONNECTION = "No connection. Try again when you have signal."

        fun normalisedHandle(text: String): String = text.trim().trim('@').lowercase()

        /** Same rule as iOS and the database: 3–20 of a–z, 0–9, _ and . */
        fun isValidHandle(handle: String): Boolean =
            handle.length in 3..20 && handle.all { it in 'a'..'z' || it in '0'..'9' || it == '_' || it == '.' }

        fun randomNonce(length: Int = 32): String {
            val characters = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
            val random = SecureRandom()
            return String(CharArray(length) { characters[random.nextInt(characters.length)] })
        }

        fun sha256(text: String): String =
            MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
