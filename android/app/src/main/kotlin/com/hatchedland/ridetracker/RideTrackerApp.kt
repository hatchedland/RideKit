package com.hatchedland.ridetracker

import android.app.Application
import com.hatchedland.ridetracker.data.AccountRepository
import com.hatchedland.ridetracker.data.makeSupabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers

/** Holds the app-wide services; plain constructor wiring, no DI framework (minimal dependencies). */
class RideTrackerApp : Application() {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val supabase by lazy { makeSupabase() }
    val account by lazy { AccountRepository(supabase, scope) }
}
