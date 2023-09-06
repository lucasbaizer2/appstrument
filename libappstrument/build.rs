use std::io::Result;

fn main() -> Result<()> {
    let proto_files = &[
        "../common/appstrument.proto",
        "../common/data_model.proto",
    ];
    for proto_file in proto_files {
        println!("cargo:rerun-if-changed={}", proto_file);
    }
    prost_build::compile_protos(proto_files, &["../common"])?;
    Ok(())
}
