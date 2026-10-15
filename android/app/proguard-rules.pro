# Rhino references the Java SE JavaBeans introspection API, which is not
# available on Android. These classes are optional to the converter path.
# This silences only the exact missing-class references reported by R8.
-dontwarn java.beans.BeanDescriptor
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor
