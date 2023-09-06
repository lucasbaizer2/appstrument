use jni::sys::*;
use std::alloc::Layout;
use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr};

#[derive(Debug)]
enum TestJvmObject {
    String(String),
    Class(String),
}

impl TestJvmObject {
    fn as_string(&self) -> &String {
        match self {
            Self::String(str) => &str,
            _ => panic!("object is not a string"),
        }
    }

    fn as_class(&self) -> &String {
        match self {
            Self::Class(str) => &str,
            _ => panic!("object is not a class"),
        }
    }
}

#[derive(Debug)]
struct TestJvm {
    objects: HashMap<usize, TestJvmObject>,
    methods: Vec<String>,
    object_nonce: usize,
}

unsafe fn take_jvm(env: *mut JNIEnv) -> Box<TestJvm> {
    let ptr = (**env).reserved0;
    Box::from_raw(ptr as *mut TestJvm)
}

unsafe fn restore_jvm(jvm: Box<TestJvm>) {
    Box::into_raw(jvm);
}

unsafe fn create_jvm_ptr(val: usize) -> *mut usize {
    Box::into_raw(Box::new(val))
}

unsafe fn deref_jvm_ptr(ptr: *mut usize) -> usize {
    let val = Box::from_raw(ptr);
    let deref = *val;
    Box::into_raw(val);
    deref
}

unsafe extern "system" fn new_string_utf(env: *mut JNIEnv, str: *const i8) -> jstring {
    let cstr = CStr::from_ptr(str).to_str().expect("cstr to &str");
    let obj = TestJvmObject::String(cstr.to_string());

    let mut jvm = take_jvm(env);
    let object_nonce = jvm.object_nonce;
    jvm.objects.insert(object_nonce, obj);
    jvm.object_nonce += 1;

    restore_jvm(jvm);

    create_jvm_ptr(object_nonce) as *mut _jobject
}

unsafe extern "system" fn exception_check(_env: *mut JNIEnv) -> jboolean {
    0
}

unsafe extern "system" fn find_class(env: *mut JNIEnv, name: *const c_char) -> jclass {
    let cstr = CStr::from_ptr(name).to_str().expect("cstr to &str");
    let obj = TestJvmObject::Class(cstr.to_string());

    let mut jvm = take_jvm(env);
    let object_nonce = jvm.object_nonce;
    jvm.objects.insert(object_nonce, obj);
    jvm.object_nonce += 1;

    restore_jvm(jvm);

    create_jvm_ptr(object_nonce) as *mut _jobject
}

unsafe extern "system" fn get_static_method_id(
    env: *mut JNIEnv,
    clazz: jclass,
    name: *const c_char,
    sig: *const c_char,
) -> jmethodID {
    let method_name = CStr::from_ptr(name)
        .to_str()
        .expect("cstr to &str")
        .to_string();
    let method_signature = CStr::from_ptr(sig)
        .to_str()
        .expect("cstr to &str")
        .to_string();

    let mut jvm = take_jvm(env);
    let class_name = jvm
        .objects
        .get(&deref_jvm_ptr(clazz as *mut usize))
        .expect("invalid class object")
        .as_class();
    let full_method_name = format!("{}.{}{}", class_name, method_name, method_signature);
    let method_nonce = jvm.methods.len();
    jvm.methods.push(full_method_name);
    restore_jvm(jvm);

    create_jvm_ptr(method_nonce) as *mut _jmethodID
}

unsafe extern "system" fn call_static_object_method_a(
    env: *mut JNIEnv,
    _clazz: jclass,
    method_id: jmethodID,
    args: *const jvalue,
) -> jobject {
    let jvm = take_jvm(env);

    let method = &jvm.methods[deref_jvm_ptr(method_id as *mut usize)];
    if method == "appstrument/server/ReflectionUtil.findStaticFieldSignature(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;" {
        let args = std::slice::from_raw_parts(args, 2);
        let arg0 = jvm
            .objects
            .get(&deref_jvm_ptr(args[0].l as *mut usize))
            .expect("invalid class object")
            .as_string();
        let arg1 = jvm
            .objects
            .get(&deref_jvm_ptr(args[1].l as *mut usize))
            .expect("invalid class object")
            .as_string();
        println!("findStaticFieldSignature: {}.{}", arg0, arg1);
        if arg0 == "appstrument/server/ReflectionUtil" && arg1 == "testFieldObj" {
            return create_jvm_ptr(100) as *mut jni::sys::_jobject;
        }
    }

    restore_jvm(jvm);

    std::ptr::null_mut()
}

pub fn create_mock_jvm<'a>() -> jni::JNIEnv<'a> {
    unsafe {
        let test_jvm = TestJvm {
            objects: HashMap::new(),
            methods: Vec::new(),
            object_nonce: 1,
        };

        let env_memory = std::alloc::alloc(Layout::new::<JNINativeInterface_>());
        let mut sys_env = env_memory as *mut JNINativeInterface_;
        (*sys_env).reserved0 = Box::into_raw(Box::new(test_jvm)) as *mut c_void;
        (*sys_env).NewStringUTF = Some(new_string_utf);
        (*sys_env).ExceptionCheck = Some(exception_check);
        (*sys_env).FindClass = Some(find_class);
        (*sys_env).GetStaticMethodID = Some(get_static_method_id);
        (*sys_env).CallStaticObjectMethodA = Some(call_static_object_method_a);

        let sys_env_ptr = &mut (sys_env as *const JNINativeInterface_);
        jni::JNIEnv::from_raw(sys_env_ptr).unwrap()
    }
}
