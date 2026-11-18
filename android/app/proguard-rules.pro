# kotlinx.serialization: keep generated serializers for the Supabase row classes.
-keepclassmembers @kotlinx.serialization.Serializable class com.hatchedland.ridetracker.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
