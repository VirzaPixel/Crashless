# Keep TensorFlow Lite classes
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }

# Keep FFI classes
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
