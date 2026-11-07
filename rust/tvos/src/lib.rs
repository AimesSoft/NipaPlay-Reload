//! tvOS uses the same authenticated Mesh transport as every other device,
//! without linking desktop renderers, the downloader, or desktop vaults.
use serde_json::{json, Value};
use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
    sync::OnceLock,
};
#[path = "../../src/api/mesh.rs"]
mod mesh;

fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("tvOS Mesh runtime")
    })
}
fn string(v: &Value, key: &str) -> Result<String, String> {
    v[key]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| format!("invalid {key}"))
}
fn dispatch(v: Value) -> Result<Value, String> {
    let id = || {
        v["id"]
            .as_u64()
            .and_then(|n| u32::try_from(n).ok())
            .ok_or("invalid id")
    };
    Ok(match v["operation"].as_str().ok_or("invalid operation")? {
        "mesh_generate_key" => json!(mesh::mesh_generate_key()?),
        "mesh_public_key" => json!(mesh::mesh_public_key(string(&v, "private_key")?)?),
        "mesh_sign" => json!(mesh::mesh_sign(
            string(&v, "private_key")?,
            string(&v, "message")?
        )?),
        "mesh_validate_certificate" => json!(mesh::mesh_validate_certificate(
            string(&v, "ca")?,
            string(&v, "certificate")?,
            string(&v, "private_key")?,
            string(&v, "account")?
        )?),
        "mesh_start" => json!(runtime().block_on(mesh::mesh_start(
            string(&v, "ca")?,
            string(&v, "certificate")?,
            string(&v, "private_key")?,
            string(&v, "account")?,
            serde_json::from_value(v["allowed"].clone()).map_err(|_| "invalid allowed")?,
            string(&v, "bind")?
        ))?),
        "mesh_port" => json!(mesh::mesh_port(id()?)?),
        "mesh_update_devices" => {
            mesh::mesh_update_devices(
                id()?,
                serde_json::from_value(v["allowed"].clone()).map_err(|_| "invalid allowed")?,
            )?;
            Value::Null
        }
        "mesh_stop" => {
            mesh::mesh_stop(id()?)?;
            Value::Null
        }
        "mesh_next" => {
            let e = runtime().block_on(mesh::mesh_next(id()?))?;
            json!({"request_id":e.request_id,"device_id":e.device_id,"body":e.body})
        }
        "mesh_respond" => {
            mesh::mesh_respond(
                id()?,
                v["request_id"].as_u64().ok_or("invalid request_id")?,
                string(&v, "body")?,
            )?;
            Value::Null
        }
        "mesh_send" => json!(runtime().block_on(mesh::mesh_send(
            id()?,
            string(&v, "host")?,
            v["port"]
                .as_u64()
                .and_then(|n| u16::try_from(n).ok())
                .ok_or("invalid port")?,
            string(&v, "device")?,
            string(&v, "body")?
        ))?),
        _ => return Err("unsupported television native operation".into()),
    })
}

/// Owned UTF-8 JSON, with the same off-isolate ABI used by the headless host.
#[no_mangle]
pub unsafe extern "C" fn nipaplay_headless_call(input: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if input.is_null() {
            return Err("null input".to_owned());
        }
        let text = CStr::from_ptr(input)
            .to_str()
            .map_err(|_| "invalid UTF-8".to_owned())?;
        dispatch(serde_json::from_str(text).map_err(|_| "invalid JSON".to_owned())?)
    });
    let envelope = match result {
        Ok(Ok(value)) => json!({"result":value}),
        Ok(Err(error)) => json!({"error":error}),
        Err(_) => json!({"error":"television native panic"}),
    };
    CString::new(envelope.to_string()).unwrap().into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn nipaplay_headless_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}
