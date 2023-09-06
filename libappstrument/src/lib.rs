#![feature(strict_provenance)]

pub mod proto {
    include!(concat!(env!("OUT_DIR"), "/appstrument.protobuf.rs"));
}
pub mod java;
pub mod slat;

#[cfg(test)]
mod test;

#[cfg(test)]
mod tests {
    use pest::Parser;
    use crate::slat::{
        interpreter::SlatInterpreter,
        parser::{Rule, SlatParser, self},
    };

    #[test]
    fn it_works() {
        let tree = SlatParser::parse(Rule::program, "ReflectionUtil.stringArray[1]").expect("parsed");
        // println!("{:#?}", tree);

        let ast = parser::parse("ReflectionUtil.stringArray[1]").expect("parsed");
        println!("{:#?}", ast);

        return;

        let env = crate::test::jvm::create_mock_jvm();
        let mut interpreter = SlatInterpreter::new(env);
        interpreter
            .interpret("import appstrument.server.ReflectionUtil")
            .unwrap();
        interpreter
            .interpret("ReflectionUtil.stringArray[1]")
            .unwrap();
    }
}
