# Firebase and Credential Manager ship their own consumer rules; kotlinx.serialization keeps its serializers.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
# ONNX Runtime's native code finds its Java classes by name (OrtException, OrtSession$Result, TensorInfo, …):
# renaming them breaks listening in a release build.
-keep class ai.onnxruntime.** { *; }
