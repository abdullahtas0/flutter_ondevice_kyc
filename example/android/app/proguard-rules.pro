# ONNX Runtime looks these classes up by name from JNI. R8 must not rename them.
-keep class ai.onnxruntime.** { *; }
-keep class com.masicai.flutteronnxruntime.** { *; }
