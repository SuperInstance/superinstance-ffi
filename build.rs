use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let config = cbindgen::Config::from_root_or_default(PathBuf::from(&crate_dir).as_path());
    cbindgen::Builder::new()
        .with_crate(PathBuf::from(&crate_dir))
        .with_config(config)
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(PathBuf::from(&crate_dir).join("superinstance-ffi.h"));
}
