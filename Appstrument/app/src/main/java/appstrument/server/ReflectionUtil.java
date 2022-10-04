package appstrument.server;

import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Member;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

public class ReflectionUtil {
    private static final JavaField testFieldObj = new JavaField("test field", "str 1", "str 2");
    private static int[] intArray = new int[] { 1, 2, 3, 4, 5, 9, 8, 7, 6 };
    private static List<Double> doubleList = new ArrayList<>();
    private static String[] stringArray = new String[] { "hello, ", "world", "!"};

    static {
        doubleList.add(10.0);
        doubleList.add(3.14);
        doubleList.add(99999.0);
    }

    private static String getTypeName(Class<?> type) {
        String name = type.getName();
        if (!name.startsWith("[")) {
            return name;
        }

        StringBuilder arrayBuilder = new StringBuilder();
        while (name.startsWith("[")) {
            arrayBuilder.append("[]");
            name = name.substring(1);
        }

        return parseTypeSignature(name).getName() + arrayBuilder;
    }

    private static Class<?> parseTypeSignature(String signature) {
        char type = signature.charAt(0);
        switch (type) {
            case 'B':
                return byte.class;
            case 'S':
                return short.class;
            case 'I':
                return int.class;
            case 'J':
                return long.class;
            case 'F':
                return float.class;
            case 'D':
                return double.class;
            case 'C':
                return char.class;
            case 'Z':
                return boolean.class;
            case 'V':
                return void.class;
            case 'L':
                String internalName = signature.substring(1, signature.length() - 1);
                return parseInternalName(internalName);
            case '[':
                Class<?> componentType = parseTypeSignature(signature.substring(1));
                return Array.newInstance(componentType, 0).getClass();
            default:
                throw new AppstrumentException("invalid type signature");
        }
    }

    private static Class<?> parseInternalName(String name) {
        try {
            return Class.forName(name.replace('/', '.'));
        } catch (ClassNotFoundException e) {
            throw new AppstrumentException(name);
        }
    }

    private static String getTypeSignature(Class<?> type) {
        if (type.isArray()) {
            return "[" + getTypeSignature(type.getComponentType());
        } else if (type.isPrimitive()) {
            if (type == byte.class) {
                return "B";
            }
            if (type == short.class) {
                return "S";
            }
            if (type == int.class) {
                return "I";
            }
            if (type == long.class) {
                return "J";
            }
            if (type == float.class) {
                return "F";
            }
            if (type == double.class) {
                return "D";
            }
            if (type == char.class) {
                return "C";
            }
            if (type == boolean.class) {
                return "Z";
            }
            if (type == void.class) {
                return "V";
            }
            throw new AppstrumentException("invalid primitive type: " + type);
        }
        return "L" + type.getName().replace('.', '/') + ";";
    }

    private static List<Method> getAllMethods(Class<?> cls, MemberType type) {
        List<Method> methods = Arrays.stream(cls.getDeclaredMethods()).filter(type::filter).collect(Collectors.toList());
        if (cls.getSuperclass() != null) {
            methods.addAll(getAllMethods(cls.getSuperclass(), type));
        }
        return methods;
    }

    private static String getMethodSignature(Method method) {
        StringBuilder sb = new StringBuilder("(");
        for (Class<?> parType : method.getParameterTypes()) {
            sb.append(getTypeSignature(parType));
        }
        sb.append(")");
        sb.append(getTypeSignature(method.getReturnType()));
        return sb.toString();
    }

    private static Method findMatchingMethod(List<Method> methods, String name, Class<?>[] typeHints) {
        outer:
        for (Method method : methods) {
            if (!method.getName().equals(name)) {
                continue;
            }
            if (method.getParameterTypes().length != typeHints.length) {
                continue;
            }

            Class<?>[] params = method.getParameterTypes();
            for (int i = 0; i < typeHints.length; i++) {
                Class<?> typeHint = typeHints[i];
                if (!params[i].isAssignableFrom(typeHint)) {
                    continue outer;
                }
            }

            return method;
        }
        return null;
    }

    public static String findMethodSignature(String className, String methodName, String[] typeHints, MemberType type) {
        Method m = findMatchingMethod(
                getAllMethods(parseInternalName(className), type),
                methodName,
                Arrays.stream(typeHints).map(ReflectionUtil::parseTypeSignature).toArray(Class[]::new));
        if (m == null) {
            return null;
        }
        return getMethodSignature(m);
    }

    public static String findStaticMethodSignature(String className, String methodName, String[] typeHints) {
        return findMethodSignature(className, methodName, typeHints, MemberType.STATIC);
    }

    public static String findInstanceMethodSignature(Object obj, String methodName, String[] typeHints) {
        String className = obj.getClass().getName().replace('.', '/');
        return findMethodSignature(className, methodName, typeHints, MemberType.INSTANCE);
    }

    private static List<Field> getAllFields(Class<?> cls, MemberType type) {
        List<Field> fields = Arrays.stream(cls.getDeclaredFields()).filter(type::filter).collect(Collectors.toList());
        if (cls.getSuperclass() != null) {
            fields.addAll(getAllFields(cls.getSuperclass(), type));
        }
        return fields;
    }

    private static Field findMatchingField(List<Field> fields, String name) {
        return fields.stream().filter(field -> field.getName().equals(name)).findFirst().orElse(null);
    }

    public static String findFieldSignature(Class<?> cls, String fieldName, MemberType type) {
        Field f = findMatchingField(getAllFields(cls, type), fieldName);
        if (f == null) {
            return null;
        }
        return getTypeSignature(f.getType());
    }

    public static String findStaticFieldSignature(String className, String fieldName) {
        return findFieldSignature(parseInternalName(className), fieldName, MemberType.STATIC);
    }

    public static String findInstanceFieldSignature(Object instance, String fieldName) {
        return findFieldSignature(instance.getClass(), fieldName, MemberType.INSTANCE);
    }

    public static JavaField[] findStaticFields(String className) {
        return getAllFields(parseInternalName(className), MemberType.STATIC)
                .stream()
                .map(field -> new JavaField(
                        field.getName(),
                        getTypeName(field.getType()),
                        getTypeSignature(field.getType())))
                .toArray(JavaField[]::new);
    }

    public static JavaField[] findObjectFields(Object obj) {
        return getAllFields(obj.getClass(), MemberType.INSTANCE)
                .stream()
                .map(field -> new JavaField(
                        field.getName(),
                        getTypeName(field.getType()),
                        getTypeSignature(field.getType())))
                .toArray(JavaField[]::new);
    }

    public static boolean doesClassExist(String name) {
        try {
            Class.forName(name);
            return true;
        } catch (ReflectiveOperationException e) {
            return false;
        }
    }

    public static boolean isListType(Object value) {
        Class<?> type = value.getClass();
        if (type.isArray()) {
            return true;
        }

        while (type.getSuperclass() != null) {
            Class<?>[] interfaces = type.getInterfaces();
            for (Class<?> iface : interfaces) {
                if (iface.equals(List.class)) {
                    return true;
                }
            }
            type = type.getSuperclass();
        }

        return false;
    }

    public static Object[] getListAsArray(Object listObj) {
        if (listObj.getClass().isArray()) {
            Class<?> componentType = listObj.getClass().getComponentType();
            Object[] arr = new Object[Array.getLength(listObj)];
            for (int i = 0; i < arr.length; i++) {
                Object val;
                if (componentType == byte.class) {
                    val = Array.getByte(listObj, i);
                } else if (componentType == short.class) {
                    val = Array.getShort(listObj, i);
                } else if (componentType == int.class) {
                    val = Array.getInt(listObj, i);
                } else if (componentType == long.class) {
                    val = Array.getLong(listObj, i);
                } else if (componentType == float.class) {
                    val = Array.getFloat(listObj, i);
                } else if (componentType == double.class) {
                    val = Array.getDouble(listObj, i);
                } else if (componentType == char.class) {
                    val = Array.getChar(listObj, i);
                } else if (componentType == boolean.class) {
                    val = Array.getBoolean(listObj, i);
                } else {
                    val = Array.get(listObj, i);
                }
                arr[i] = val;
            }
            return arr;
        }

        List<?> list = (List<?>) listObj;
        List<?> copy = new ArrayList<>(list); // make a copy to avoid concurrency issues
        Object[] arr = new Object[copy.size()];
        for (int i = 0; i < copy.size(); i++) {
            arr[i] = copy.get(i);
        }
        return arr;
    }

    private enum MemberType {
        STATIC,
        INSTANCE;

        public boolean filter(Member member) {
            if (this == STATIC) {
                return Modifier.isStatic(member.getModifiers());
            }
            return !Modifier.isStatic(member.getModifiers());
        }
    }
}
