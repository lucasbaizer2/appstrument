use std::{io::Cursor, panic, sync::Mutex};

use crate::{
    proto::{java_value::JavaValueType, *},
    slat::interpreter::SlatInterpreter,
};
use anyhow::anyhow;
use jni::{
    objects::{GlobalRef, JClass, JObject, JString, JValue},
    sys::{jbyteArray, jint},
    *,
};
use lazy_static::lazy_static;
use prost::*;

pub struct JavaNativeContext {
    pub interpreter: SlatInterpreter,
    pub last_error: Option<anyhow::Error>,
    pub stored_objects: Vec<GlobalRef>,
}

#[derive(Copy, Clone)]
struct ThreadSafeVM(*mut sys::JavaVM);
unsafe impl Sync for ThreadSafeVM {}
unsafe impl Send for ThreadSafeVM {}

lazy_static! {
    static ref JAVA_VM: Mutex<ThreadSafeVM> = Mutex::new(ThreadSafeVM(std::ptr::null_mut()));
}

trait WrappableResult {
    fn throw_wrappable(self, env: JNIEnv);
}

impl WrappableResult for jni::errors::Error {
    fn throw_wrappable(self, env: JNIEnv) {
        // don't throw a new exception if there is already one pending
        if !matches!(self, jni::errors::Error::JavaException) {
            let error_text = format!("{}", self);
            env.throw_new("appstrument/server/AppstrumentException", error_text)
                .expect("could not throw exception");
        }
    }
}

impl WrappableResult for anyhow::Error {
    fn throw_wrappable(self, env: JNIEnv) {
        if self.is::<jni::errors::Error>() {
            let jni_error = self.downcast::<jni::errors::Error>().expect("unreachable");
            jni_error.throw_wrappable(env);
        } else {
            let error_text = format!("{}", self);
            env.throw_new("appstrument/server/AppstrumentException", error_text)
                .expect("could not throw exception");
        }
    }
}

pub fn serialize_jvalue(
    env: JNIEnv,
    mut ctx: Option<&mut JavaNativeContext>,
    val: JValue<'_>,
) -> anyhow::Result<JavaValue> {
    Ok(match val {
        JValue::Void => JavaValue {
            value_type: JavaValueType::NotPresent as i32,
            value: None,
        },
        JValue::Object(obj) => {
            if obj.is_null() {
                JavaValue {
                    value_type: JavaValueType::NullObject as i32,
                    value: None,
                }
            } else {
                let class_obj = env.get_object_class(obj)?;
                let class_name = env
                    .call_method(class_obj, "getName", "()Ljava/lang/String;", &[])?
                    .l()?;
                let class_name = env.get_string(JString::from(class_name))?.into();
                if class_name == "java.lang.String" {
                    let string_value = env.get_string(JString::from(obj))?.into();

                    JavaValue {
                        value_type: JavaValueType::Present as i32,
                        value: Some(java_value::Value::String(string_value)),
                    }
                } else if class_name == "java.lang.Byte" {
                    let primitive_value = env.call_method(obj, "longValue", "()J", &[])?.j()?;
                    JavaValue {
                        value_type: JavaValueType::Present as i32,
                        value: Some(java_value::Value::Integer(primitive_value)),
                    }
                } else if class_name == "java.lang.Byte"
                    || class_name == "java.lang.Short"
                    || class_name == "java.lang.Integer"
                    || class_name == "java.lang.Long"
                {
                    let primitive_value = env.call_method(obj, "longValue", "()J", &[])?.j()?;
                    JavaValue {
                        value_type: JavaValueType::Present as i32,
                        value: Some(java_value::Value::Integer(primitive_value)),
                    }
                } else if class_name == "java.lang.Float" || class_name == "java.lang.Double" {
                    let primitive_value = env.call_method(obj, "doubleValue", "()D", &[])?.d()?;
                    JavaValue {
                        value_type: JavaValueType::Present as i32,
                        value: Some(java_value::Value::Decimal(primitive_value)),
                    }
                } else if class_name == "java.lang.Boolean" {
                    let primitive_value = env.call_method(obj, "booleanValue", "()Z", &[])?.z()?;
                    JavaValue {
                        value_type: JavaValueType::Present as i32,
                        value: Some(java_value::Value::Boolean(primitive_value)),
                    }
                } else if class_name == "java.lang.Character" {
                    let primitive_value = env.call_method(obj, "charValue", "()C", &[])?.c()?;
                    JavaValue {
                        value_type: JavaValueType::Present as i32,
                        value: Some(java_value::Value::Integer(primitive_value as i64)),
                    }
                } else {
                    let is_list_type = env
                        .call_static_method(
                            "appstrument/server/ReflectionUtil",
                            "isListType",
                            "(Ljava/lang/Object;)Z",
                            &[JValue::Object(obj)],
                        )?
                        .z()?;
                    if is_list_type {
                        let list_type = env
                            .call_static_method(
                                "appstrument/server/ReflectionUtil",
                                "getListAsArray",
                                "(Ljava/lang/Object;)[Ljava/lang/Object;",
                                &[JValue::Object(obj)],
                            )?
                            .l()?;
                        let array_type = list_type.into_inner();

                        let array_len = env.get_array_length(array_type)?;
                        let mut items = Vec::with_capacity(array_len as usize);
                        for i in 0..array_len {
                            let jvalue = env.get_object_array_element(array_type, i)?;
                            let serialized = serialize_jvalue(
                                env,
                                match ctx {
                                    Some(ref mut ctx) => Some(*ctx),
                                    None => None,
                                },
                                JValue::Object(jvalue),
                            )?;
                            items.push(serialized);
                        }

                        JavaValue {
                            value_type: JavaValueType::Present as i32,
                            value: Some(java_value::Value::List(JavaValueList {
                                list_type: class_name,
                                items,
                            })),
                        }
                    } else {
                        if let Some(ctx) = ctx {
                            let pinned_ref = env.new_global_ref(obj)?;
                            ctx.stored_objects.push(pinned_ref);
                        }

                        JavaValue {
                            value_type: JavaValueType::Present as i32,
                            value: Some(java_value::Value::ObjectType(class_name)),
                        }
                    }
                }
            }
        }
        JValue::Byte(integer) => JavaValue {
            value_type: JavaValueType::Present as i32,
            value: Some(java_value::Value::Integer(integer as i64)),
        },
        JValue::Short(integer) => JavaValue {
            value_type: JavaValueType::Present as i32,
            value: Some(java_value::Value::Integer(integer as i64)),
        },
        JValue::Int(integer) => JavaValue {
            value_type: JavaValueType::Present as i32,
            value: Some(java_value::Value::Integer(integer as i64)),
        },
        JValue::Long(integer) => JavaValue {
            value_type: JavaValueType::Present as i32,
            value: Some(java_value::Value::Integer(integer)),
        },
        JValue::Float(decimal) => JavaValue {
            value_type: JavaValueType::Present as i32,
            value: Some(java_value::Value::Decimal(decimal as f64)),
        },
        JValue::Double(decimal) => JavaValue {
            value_type: JavaValueType::Present as i32,
            value: Some(java_value::Value::Decimal(decimal)),
        },
        JValue::Bool(boolean) => JavaValue {
            value_type: JavaValueType::Present as i32,
            value: Some(java_value::Value::Boolean(boolean == 1)),
        },
        JValue::Char(integer) => JavaValue {
            value_type: JavaValueType::Present as i32,
            value: Some(java_value::Value::Integer(integer as i64)),
        },
    })
}

macro_rules! wrap_result {
    ( $env:expr, $result:expr ) => {{
        match $result {
            Ok(val) => val,
            Err(err) => {
                err.throw_wrappable($env);
                return std::ptr::null_mut();
            }
        }
    }};
}

#[no_mangle]
pub extern "system" fn Java_appstrument_server_AppstrumentNative_nativeInitialize<'a>(
    env: JNIEnv<'a>,
    _cls: JClass,
) {
    {
        let java_vm = env.get_java_vm().expect("could not get Java VM");
        let mut global_vm = JAVA_VM.lock().expect("could not get global VM lock");
        *global_vm = ThreadSafeVM(java_vm.get_java_vm_pointer());
    }

    panic::set_hook(Box::new(|info| {
        let java_vm = unsafe {
            let global_vm = JAVA_VM.lock().expect("could not get global VM lock");
            JavaVM::from_raw(global_vm.0).expect("construct VM")
        };
        let env = java_vm
            .attach_current_thread()
            .expect("could not attach VM to current thread");
        env.throw_new(
            "appstrument/server/AppstrumentException",
            format!("{}", info),
        )
        .expect("could not throw exception");
    }));
}

#[no_mangle]
pub extern "system" fn Java_appstrument_server_AppstrumentNative_nativeCreateContext<'a>(
    env: JNIEnv<'static>,
    _class: JClass,
) -> *mut JavaNativeContext {
    let context = Box::new(JavaNativeContext {
        interpreter: SlatInterpreter::new(env),
        last_error: None,
        stored_objects: Vec::new(),
    });
    Box::into_raw(context)
}

#[no_mangle]
pub extern "system" fn Java_appstrument_server_AppstrumentNative_nativeDestroyContext<'a>(
    _env: JNIEnv<'a>,
    _this: JObject,
    context: *mut JavaNativeContext,
) {
    unsafe {
        std::mem::drop(Box::from_raw(context));
    }
}

#[no_mangle]
pub extern "system" fn Java_appstrument_server_AppstrumentNative_nativeHandleRequest<'a, 'b>(
    env: JNIEnv<'a>,
    this: JObject,
    context: *mut JavaNativeContext,
    request_byte_array: JObject,
    request_byte_array_offset: jint,
) -> jbyteArray {
    let request_bytes = wrap_result!(env, env.convert_byte_array(request_byte_array.into_inner()));

    let mut cursor = Cursor::new(request_bytes);
    cursor.set_position(request_byte_array_offset as u64);
    let request = wrap_result!(
        env,
        AppstrumentRequest::decode(&mut cursor)
            .map_err(|_| anyhow!("could not deserialize request"))
    );

    let response_body = wrap_result!(
        env,
        match request.body.expect("no body sent in request") {
            appstrument_request::Body::LoadedClasses(_) => get_all_loaded_classes(env, this),
            appstrument_request::Body::StaticFields(req) => {
                let mut ctx = unsafe { Box::from_raw(context) };
                let static_fields = get_all_static_fields(env, req.class_name, ctx.as_mut());
                Box::into_raw(ctx);
                static_fields
            }
            appstrument_request::Body::ObjectFields(req) => {
                let mut ctx = unsafe { Box::from_raw(context) };
                let object_fields = get_all_object_fields(env, req.object_id, ctx.as_mut());
                Box::into_raw(ctx);
                object_fields
            }
            appstrument_request::Body::ExecuteSlat(req) => {
                let mut ctx = unsafe { Box::from_raw(context) };
                let interpret_result = ctx.interpreter.interpret(&req.code);
                let (result, error_text) = match interpret_result {
                    Ok(java_value) => (java_value, String::new()),
                    Err(err) => (
                        JavaValue {
                            value_type: java_value::JavaValueType::NotPresent as i32,
                            value: None,
                        },
                        err.to_string(),
                    ),
                };
                Box::into_raw(ctx);
                Ok(appstrument_response::Body::ExecuteSlat(
                    ExecuteSlatResponse {
                        error: !error_text.is_empty(),
                        text: error_text,
                        result: Some(result),
                    },
                ))
            }
            appstrument_request::Body::ProcessStatus(_) => {
                let threads = wrap_result!(env, get_threads(env));
                Ok(appstrument_response::Body::ProcessStatus(
                    GetProcessStatusResponse { threads },
                ))
            }
            _ => panic!(),
        }
    );
    let response = AppstrumentResponse {
        id: request.id,
        body: Some(response_body),
    };

    wrap_result!(env, env.byte_array_from_slice(&response.encode_to_vec()))
}

#[no_mangle]
pub extern "system" fn Java_appstrument_server_AppstrumentNative_nativeCreateLogcatPacket<
    'a,
    'b,
>(
    env: JNIEnv<'a>,
    _this: JObject,
    _context: *mut JavaNativeContext,
    text: JString,
) -> jbyteArray {
    let text: String = wrap_result!(env, env.get_string(text)).into();
    let response = AppstrumentResponse {
        id: -1,
        body: Some(appstrument_response::Body::LogcatStream(LogcatStream {
            text,
        })),
    };
    wrap_result!(env, env.byte_array_from_slice(&response.encode_to_vec()))
}

fn get_threads(env: JNIEnv) -> anyhow::Result<Vec<JavaThread>> {
    let threads = env
        .call_static_method(
            "appstrument/server/ProcessUtil",
            "getThreads",
            "()[Lappstrument/server/JavaThread;",
            &[],
        )?
        .l()?;
    let threads_array = threads.into_inner();
    let threads_len = env.get_array_length(threads_array)?;
    let mut java_threads = Vec::with_capacity(threads_len as usize);
    for i in 0..threads_len {
        let thread = env.get_object_array_element(threads_array, i)?;

        let name = env.get_field(thread, "name", "Ljava/lang/String;")?.l()?;
        let is_daemon = env.get_field(thread, "isDaemon", "Z")?.z()?;
        let stack_trace = env
            .get_field(thread, "stackTrace", "Ljava/lang/String;")?
            .l()?;

        let name: String = env.get_string(JString::from(name))?.into();
        let stack_trace: String = env.get_string(JString::from(stack_trace))?.into();

        java_threads.push(JavaThread {
            name,
            is_daemon,
            stack_trace,
        });
    }
    Ok(java_threads)
}

fn get_all_fields<'a, F: Fn(&str, &str) -> jni::errors::Result<JValue<'a>>>(
    env: JNIEnv,
    ctx: &mut JavaNativeContext,
    java_fields: JObject,
    field_accessor: F,
) -> anyhow::Result<Vec<JavaField>> {
    let fields_len = env.get_array_length(java_fields.into_inner())?;
    let mut fields = Vec::with_capacity(fields_len as usize);
    for i in 0..fields_len as i32 {
        let static_field = env.get_object_array_element(java_fields.into_inner(), i)?;

        let name_str = env
            .get_field(static_field, "name", "Ljava/lang/String;")?
            .l()?;
        let type_str = env
            .get_field(static_field, "type", "Ljava/lang/String;")?
            .l()?;
        let type_signature_str = env
            .get_field(static_field, "typeSignature", "Ljava/lang/String;")?
            .l()?;
        let name: String = env.get_string(JString::from(name_str))?.into();
        let r#type: String = env.get_string(JString::from(type_str))?.into();
        let type_signature: String = env.get_string(JString::from(type_signature_str))?.into();

        // let field_value = env.get_static_field(&class_name, &name, &type_signature)?;
        let field_value = field_accessor(name.as_str(), type_signature.as_str())?;
        let value = serialize_jvalue(env, Some(ctx), field_value)?;
        let java_field = JavaField {
            name,
            r#type,
            object_id: match value.value {
                Some(java_value::Value::ObjectType(_)) => (ctx.stored_objects.len() - 1) as i32,
                _ => -1,
            },
            value: Some(value),
        };
        fields.push(java_field);
    }
    Ok(fields)
}

fn get_all_object_fields(
    env: JNIEnv,
    object_id: i32,
    ctx: &mut JavaNativeContext,
) -> anyhow::Result<appstrument_response::Body> {
    let ref_clone = ctx.stored_objects[object_id as usize].clone();
    let object = ref_clone.as_obj();
    let instance_fields = env
        .call_static_method(
            "appstrument/server/ReflectionUtil",
            "findObjectFields",
            "(Ljava/lang/Object;)[Lappstrument/server/JavaField;",
            &[JValue::Object(object)],
        )?
        .l()?;
    let fields = get_all_fields(
        env,
        ctx,
        instance_fields,
        |name: &str, type_signature: &str| env.get_field(object, name, type_signature),
    )?;
    Ok(appstrument_response::Body::ObjectFields(
        GetObjectFieldsResponse { fields },
    ))
}

fn get_all_static_fields(
    env: JNIEnv,
    class_name: String,
    ctx: &mut JavaNativeContext,
) -> anyhow::Result<appstrument_response::Body> {
    let class_name = class_name.replace(".", "/");
    let class_name_str = env.new_string(&class_name)?;
    let static_fields = env
        .call_static_method(
            "appstrument/server/ReflectionUtil",
            "findStaticFields",
            "(Ljava/lang/String;)[Lappstrument/server/JavaField;",
            &[JValue::Object(class_name_str.into())],
        )?
        .l()?;
    let fields = get_all_fields(
        env,
        ctx,
        static_fields,
        |name: &str, type_signature: &str| env.get_static_field(&class_name, name, type_signature),
    )?;
    Ok(appstrument_response::Body::StaticFields(
        GetStaticFieldsResponse { fields },
    ))
}

fn get_all_loaded_classes(
    env: JNIEnv,
    this: JObject,
) -> anyhow::Result<appstrument_response::Body> {
    let this_class = env.get_object_class(this)?;
    let class_loader = env
        .call_method(
            this_class,
            "getClassLoader",
            "()Ljava/lang/ClassLoader;",
            &[],
        )?
        .l()?;

    // GETFIELD dalvik/system/BaseDexClassLoader.pathList Ldalvik/system/DexPathList;
    // GETFIELD dalvik/system/DexPathList.dexElements [Ldalvik/system/DexPathList$Element;
    // for element in dexElements {
    //     GETFIELD dalvik/system/DexPathList$Element.dexFile Ldalvik/system/DexFile;
    //     GETFIELD dalvik/system/DexFile.mCookie Ljava/lang/Object;
    //     INVOKESTATIC dalvik/system/DexFile.getClassNameList(Ljava/lang/Object;)[Ljava/lang/String;
    //     for className in classNameList {
    //         INVOKEVIRTUAL java/lang/ClassLoader.findLoadedClass(Ljava/lang/String;)Ljava/lang/Class;
    //         if loadedClass == null { // the class is in the classpath but not yet loaded
    //             yield { UNRESOLVED, className, false }
    //         } else {
    //             INVOKEVIRTUAL java/lang/Class.getModifiers()I
    //             yield { CLASS/INTERFACE/ENUM/ANNOTATION, className, true }
    //         }
    //     }
    // }

    let mut loaded_classes: Vec<LoadedClass> = Vec::new();

    let path_list = env
        .get_field(class_loader, "pathList", "Ldalvik/system/DexPathList;")?
        .l()?;
    let dex_elements = env
        .get_field(
            path_list,
            "dexElements",
            "[Ldalvik/system/DexPathList$Element;",
        )?
        .l()?;
    let dex_elements_length = env.get_array_length(dex_elements.into_inner())?;
    for i in 0..dex_elements_length {
        let dex_element = env.get_object_array_element(dex_elements.into_inner(), i)?;
        let dex_file = env
            .get_field(dex_element, "dexFile", "Ldalvik/system/DexFile;")?
            .l()?;
        let cookie = env.get_field(dex_file, "mCookie", "Ljava/lang/Object;")?;
        let class_name_list = env
            .call_static_method(
                "dalvik/system/DexFile",
                "getClassNameList",
                "(Ljava/lang/Object;)[Ljava/lang/String;",
                &[cookie],
            )?
            .l()?;
        let class_name_list_length = env.get_array_length(class_name_list.into_inner())?;
        for j in 0..class_name_list_length {
            let class_name_object =
                env.get_object_array_element(class_name_list.into_inner(), j)?;
            let class_name: String = env.get_string(JString::from(class_name_object))?.into();

            if class_name.contains("$$Lambda") {
                continue;
            }

            match env.call_method(
                class_loader,
                "findLoadedClass",
                "(Ljava/lang/String;)Ljava/lang/Class;",
                &[JValue::Object(class_name_object)],
            ) {
                Ok(class) => {
                    let loaded_class = class.l()?;
                    if loaded_class.is_null() {
                        loaded_classes.push(LoadedClass {
                            class_type: LoadedClassType::Unresolved as i32,
                            class_name,
                            is_loaded: false,
                        });
                    } else {
                        let modifiers = env
                            .call_method(loaded_class, "getModifiers", "()I", &[])?
                            .i()?;
                        let class_type = {
                            if (modifiers & 0x2000) == 0x2000 {
                                LoadedClassType::Annotation
                            } else if (modifiers & 0x4000) == 0x4000 {
                                LoadedClassType::Enum
                            } else if (modifiers & 0x200) == 0x200 {
                                LoadedClassType::Interface
                            } else {
                                LoadedClassType::Class
                            }
                        };
                        loaded_classes.push(LoadedClass {
                            class_type: class_type as i32,
                            class_name,
                            is_loaded: true,
                        });
                    }
                }
                Err(err) => match err {
                    jni::errors::Error::JavaException => {
                        env.exception_clear()?;
                        continue;
                    }
                    other_err => return Err(other_err.into()),
                },
            }
        }
    }

    Ok(appstrument_response::Body::LoadedClasses(
        GetLoadedClassesResponse {
            classes: loaded_classes,
        },
    ))
}
