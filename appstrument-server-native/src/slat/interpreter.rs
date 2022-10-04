use std::collections::HashMap;

use anyhow::anyhow;
use jni::{
    objects::{GlobalRef, JObject, JString, JValue},
    sys::jobject,
    JNIEnv,
};

use crate::{
    java::serialize_jvalue,
    proto::{java_value::JavaValueType, JavaValue},
};

use super::{
    ast::{ArrayExpression, Assignment, Literal, MemberExpression, MethodCall, Token},
    parser,
};

#[derive(thiserror::Error, Debug)]
pub enum InterpreterError {
    #[error("Malformed expression: {0}")]
    MalformedSlat(String),
    #[error("No such class with name '{0}' could be found")]
    NoSuchClass(String),
    #[error("Could not resolve method '{0}'")]
    NoSuchMethod(String),
    #[error("Could not resolve field '{0}'")]
    NoSuchField(String),
    #[error("A class has already been imported with name '{0}'")]
    DuplicateImport(String),
    #[error("Array index out of bounds")]
    ArrayIndexOutOfBounds,
    #[error("Unknown identifier '{0}'")]
    UnknownIdentifier(String),
}

#[derive(Debug, Clone)]
enum InterpreterValue {
    ClassRef(String),
    ObjectRef(JValue<'static>),
}

static mut OBJ_PTR: jobject = std::ptr::null_mut();

impl InterpreterValue {
    fn into_object_ref(self) -> anyhow::Result<JValue<'static>> {
        match self {
            Self::ObjectRef(val) => Ok(val),
            Self::ClassRef(_) => Err(anyhow!("expecting object reference")),
        }
    }
}

pub struct SlatInterpreter {
    env: JNIEnv<'static>,
    value_stack: Vec<InterpreterValue>,
    imports: HashMap<String, String>,
    primitive_variables: HashMap<String, JValue<'static>>,
    object_variables: HashMap<String, GlobalRef>,
}

impl SlatInterpreter {
    pub fn new(env: JNIEnv<'static>) -> SlatInterpreter {
        SlatInterpreter {
            env,
            value_stack: Vec::new(),
            imports: HashMap::new(),
            primitive_variables: HashMap::new(),
            object_variables: HashMap::new(),
        }
    }

    pub fn interpret(&mut self, slat_code: &str) -> anyhow::Result<JavaValue> {
        let ast = parser::parse(slat_code)?;

        for token in ast {
            self.visit(token)?;
        }

        if !self.value_stack.is_empty() {
            let last_value = self.value_stack.pop().expect("unreachable");
            self.value_stack.clear();
            Ok(serialize_jvalue(
                self.env,
                None,
                last_value.into_object_ref()?,
            )?)
        } else {
            Ok(JavaValue {
                value_type: JavaValueType::NotPresent as i32,
                value: None,
            })
        }
    }

    fn visit(&mut self, token: Token) -> anyhow::Result<()> {
        match token {
            Token::MethodCall(method_call) => self.visit_method_call(method_call)?,
            Token::Literal(literal) => self.visit_literal(literal)?,
            Token::Import(import) => self.visit_import(import)?,
            Token::MemberExpression(member_expr) => self.visit_member_expression(member_expr)?,
            Token::ArrayExpression(array_expr) => self.visit_array_expression(array_expr)?,
            Token::Assignment(assignment) => self.visit_assignment(assignment)?,
            Token::Identifier(ident) => self.visit_identifier(ident)?,
        };
        Ok(())
    }

    fn visit_field_access(
        &mut self,
        owner: InterpreterValue,
        field_name: String,
    ) -> anyhow::Result<()> {
        match owner {
            InterpreterValue::ClassRef(cls) => {
                let class_name_jstr = self.env.new_string(&cls)?;
                let field_name_jstr = self.env.new_string(&field_name)?;
                let signature_object = self
                    .env
                    .call_static_method(
                        "appstrument/server/ReflectionUtil",
                        "findStaticFieldSignature",
                        "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
                        &[
                            JValue::Object(*class_name_jstr),
                            JValue::Object(*field_name_jstr),
                        ],
                    )?
                    .l()?;
                if signature_object.is_null() {
                    return Err(InterpreterError::NoSuchField(field_name).into());
                }
                let signature_str: String =
                    self.env.get_string(JString::from(signature_object))?.into();
                let result = self.env.get_static_field(cls, field_name, signature_str)?;
                self.value_stack.push(InterpreterValue::ObjectRef(result));
            }
            InterpreterValue::ObjectRef(obj) => {
                let field_name_jstr = self.env.new_string(&field_name)?;
                let signature_object = self
                    .env
                    .call_static_method(
                        "appstrument/server/ReflectionUtil",
                        "findInstanceFieldSignature",
                        "(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/String;",
                        &[obj, JValue::Object(*field_name_jstr)],
                    )?
                    .l()?;
                if signature_object.is_null() {
                    return Err(InterpreterError::NoSuchField(field_name).into());
                }
                let signature_str: String =
                    self.env.get_string(JString::from(signature_object))?.into();
                let result = self.env.get_field(obj.l()?, field_name, signature_str)?;
                self.value_stack.push(InterpreterValue::ObjectRef(result));
            }
        }
        Ok(())
    }

    fn visit_identifier(&mut self, ident: String) -> anyhow::Result<()> {
        if let Some(object) = self.object_variables.get(&ident) {
            unsafe {
                let obj = object.as_obj();
                OBJ_PTR = obj.into_inner();
                self.value_stack
                    .push(InterpreterValue::ObjectRef(JValue::Object(JObject::from(
                        OBJ_PTR,
                    ))));
            }

            Ok(())
        } else if let Some(primitive) = self.primitive_variables.get(&ident) {
            self.value_stack
                .push(InterpreterValue::ObjectRef(*primitive));
            Ok(())
        } else {
            Err(InterpreterError::UnknownIdentifier(ident).into())
        }
    }

    fn visit_assignment(&mut self, assignment: Assignment) -> anyhow::Result<()> {
        self.visit(*assignment.expr)?;
        let value = self
            .value_stack
            .pop()
            .ok_or(InterpreterError::MalformedSlat(
                "expecting value".to_owned(),
            ))?
            .into_object_ref()?;

        match value {
            JValue::Object(obj) => {
                let pinned_ref = self.env.new_global_ref(obj)?;
                self.object_variables
                    .insert(assignment.variable, pinned_ref);
            }
            primitive => {
                self.primitive_variables
                    .insert(assignment.variable, primitive);
            }
        }

        Ok(())
    }

    fn visit_array_expression(&mut self, array_expr: ArrayExpression) -> anyhow::Result<()> {
        self.visit(*array_expr.array)?;
        let array = self
            .value_stack
            .pop()
            .ok_or(InterpreterError::MalformedSlat(
                "expecting array".to_owned(),
            ))?
            .into_object_ref()?
            .l()?;
        self.visit(*array_expr.index)?;
        let index = self
            .value_stack
            .pop()
            .ok_or(InterpreterError::MalformedSlat(
                "expecting array index".to_owned(),
            ))?
            .into_object_ref()?
            .i()?;
        if index < 0 {
            return Err(InterpreterError::ArrayIndexOutOfBounds.into());
        }

        let list_type = self
            .env
            .call_static_method(
                "appstrument/server/ReflectionUtil",
                "getListAsArray",
                "(Ljava/lang/Object;)[Ljava/lang/Object;",
                &[JValue::Object(array)],
            )?
            .l()?;
        let array_type = list_type.into_inner();
        let array_length = self.env.get_array_length(array_type)?;
        if index >= array_length {
            return Err(InterpreterError::ArrayIndexOutOfBounds.into());
        }

        let indexed_value = self.env.get_object_array_element(array_type, index)?;

        self.value_stack
            .push(InterpreterValue::ObjectRef(JValue::Object(indexed_value)));

        Ok(())
    }

    fn visit_member_expression(&mut self, member_expr: MemberExpression) -> anyhow::Result<()> {
        let root = match *member_expr.owner {
            Token::Identifier(class_name) => class_name,
            _ => {
                return Err(InterpreterError::MalformedSlat(
                    "member expression has invalid owner".to_owned(),
                )
                .into())
            }
        };
        if let Some(import) = self.imports.get(&root) {
            self.value_stack
                .push(InterpreterValue::ClassRef(import.clone()));
        } else {
            return Err(InterpreterError::NoSuchClass(root).into());
        }

        for member in member_expr.members {
            match member {
                Token::Identifier(field_name) => {
                    if let Some(stack_top) = self.value_stack.pop() {
                        let stack_top = stack_top.clone();
                        self.visit_field_access(stack_top, field_name)?;
                    } else {
                        return Err(InterpreterError::MalformedSlat(format!(
                            "invalid member access: no value on stack proceeding identifier: {}",
                            field_name
                        ))
                        .into());
                    }
                }
                member => self.visit(member)?,
            }
        }

        Ok(())
    }

    fn visit_import(&mut self, import: Vec<String>) -> anyhow::Result<()> {
        let class_name = &import[import.len() - 1];
        if self.imports.contains_key(class_name) {
            Err(InterpreterError::DuplicateImport(class_name.clone()).into())
        } else {
            let full_name = import.join(".");
            let class_name_jstr = self.env.new_string(&full_name)?;
            let class_exists = self
                .env
                .call_static_method(
                    "appstrument/server/ReflectionUtil",
                    "doesClassExist",
                    "(Ljava/lang/String;)Z",
                    &[JValue::Object(class_name_jstr.into())],
                )?
                .z()?;
            if class_exists {
                self.imports.insert(class_name.clone(), import.join("/"));
                Ok(())
            } else {
                Err(InterpreterError::NoSuchClass(full_name).into())
            }
        }
    }

    fn visit_method_call(&mut self, mut method_call: MethodCall) -> anyhow::Result<()> {
        let args_len = method_call.args.len();
        while !method_call.args.is_empty() {
            let arg = method_call.args.pop().expect("unreachable");
            self.visit(arg)?;
        }

        let mut args_values = Vec::with_capacity(args_len);
        for _ in 0..args_len {
            args_values.push(
                self.value_stack
                    .pop()
                    .expect("stack underflow")
                    .into_object_ref()?,
            );
        }

        let type_hints =
            self.env
                .new_object_array(args_len as i32, "java/lang/String", JObject::null())?;
        for i in 0..args_len {
            // let arg = &args_values[i];
            let arg_type = self.env.new_string("V")?;
            self.env
                .set_object_array_element(type_hints, i as i32, arg_type)?;
        }
        let type_hints = JObject::from(type_hints.to_owned());

        let value_ref = self.value_stack.pop().expect("stack underflow");
        match value_ref {
            InterpreterValue::ClassRef(class) => {
                let class_name_jstr = self.env.new_string(&class)?;
                let method_name_jstr = self.env.new_string(&method_call.name)?;
                let signature_object = self.env.call_static_method(
                    "appstrument/server/ReflectionUtil",
                    "findStaticMethodSignature",
                    "(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;)Ljava/lang/String;",
                    &[
                        JValue::Object(*class_name_jstr),
                        JValue::Object(*method_name_jstr),
                        JValue::Object(type_hints),
                    ],
                )?.l()?;
                if signature_object.is_null() {
                    return Err(InterpreterError::NoSuchMethod(method_call.name).into());
                }
                let signature_str: String =
                    self.env.get_string(JString::from(signature_object))?.into();
                let result = self.env.call_static_method(
                    class,
                    method_call.name,
                    signature_str,
                    &args_values,
                )?;
                self.value_stack.push(InterpreterValue::ObjectRef(result));
            }
            InterpreterValue::ObjectRef(object_instance) => {
                let method_name_jstr = self.env.new_string(&method_call.name)?;
                let signature_object = self.env.call_static_method(
                    "appstrument/server/ReflectionUtil",
                    "findInstanceMethodSignature",
                    "(Ljava/lang/Object;Ljava/lang/String;[Ljava/lang/String;)Ljava/lang/String;",
                    &[
                        object_instance,
                        JValue::Object(*method_name_jstr),
                        JValue::Object(type_hints),
                    ],
                )?.l()?;
                if signature_object.is_null() {
                    return Err(InterpreterError::NoSuchMethod(method_call.name).into());
                }
                let signature_str: String =
                    self.env.get_string(JString::from(signature_object))?.into();
                let result = self.env.call_method(
                    object_instance.l()?,
                    method_call.name,
                    signature_str,
                    &args_values,
                )?;
                self.value_stack.push(InterpreterValue::ObjectRef(result));
            }
        };
        Ok(())
    }

    fn visit_literal(&mut self, literal: Literal) -> anyhow::Result<()> {
        let java_literal = match literal {
            Literal::Boolean(b) => JValue::Bool(if b { 1 } else { 0 }),
            Literal::String(s) => {
                let jstring = self.env.new_string(s)?;
                JValue::Object(*jstring)
            }
            Literal::Decimal(d) => JValue::Float(d as f32),
            Literal::Integer(i) => JValue::Int(i as i32),
        };
        self.value_stack
            .push(InterpreterValue::ObjectRef(java_literal));
        Ok(())
    }
}
