use std::{ffi::{CStr, CString}, os::raw::c_char, sync::OnceLock};
use serde_json::{Value, json};
#[path = "../../src/api/mesh.rs"] mod mesh;
#[path = "../../src/api/torrent.rs"] mod torrent;

fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| tokio::runtime::Builder::new_multi_thread().worker_threads(2)
        .enable_all().build().expect("headless mesh runtime"))
}
fn string(v: &Value, key: &str) -> Result<String, String> {
    v[key].as_str().map(str::to_owned).ok_or_else(|| format!("invalid {key}"))
}
fn integer(v: &Value, key: &str) -> Result<i32, String> {
    v[key].as_i64().and_then(|n| n.try_into().ok()).ok_or_else(|| format!("invalid {key}"))
}
fn strings(v: &Value, key: &str) -> Result<Vec<String>, String> {
    serde_json::from_value(v[key].clone()).map_err(|_| format!("invalid {key}"))
}
fn dispatch(v: Value) -> Result<Value, String> {
    let id = || integer(&v, "id").map(|n| n as u32);
    let file_indices = || serde_json::from_value(v.get("only_files").cloned().unwrap_or(Value::Null))
        .map_err(|_| "invalid only_files".to_owned());
    let result = match v["operation"].as_str().ok_or("invalid operation")? {
        "storage" => torrent::disk_space(&string(&v,"path")?),
        "configure" => { torrent::configure_headless(string(&v,"root")?, string(&v,"configuration")?)?; Value::Null },
        "mesh_generate_key" => json!(mesh::mesh_generate_key()?),
        "mesh_public_key" => json!(mesh::mesh_public_key(string(&v, "private_key")?)?),
        "mesh_sign" => json!(mesh::mesh_sign(string(&v, "private_key")?, string(&v, "message")?)?),
        "mesh_validate_certificate" => json!(mesh::mesh_validate_certificate(string(&v,"ca")?,string(&v,"certificate")?,string(&v,"private_key")?,string(&v,"account")?)?),
        "mesh_start" => json!(runtime().block_on(mesh::mesh_start(string(&v,"ca")?,string(&v,"certificate")?,string(&v,"private_key")?,string(&v,"account")?,strings(&v,"allowed")?,string(&v,"bind")?))?),
        "mesh_port" => json!(mesh::mesh_port(id()?)?),
        "mesh_update_devices" => { mesh::mesh_update_devices(id()?, strings(&v,"allowed")?)?; Value::Null },
        "mesh_stop" => { mesh::mesh_stop(id()?)?; Value::Null },
        "mesh_next" => { let e = runtime().block_on(mesh::mesh_next(id()?))?; json!({"request_id":e.request_id,"device_id":e.device_id,"body":e.body}) },
        "mesh_respond" => { mesh::mesh_respond(id()?, v["request_id"].as_u64().ok_or("invalid request_id")?, string(&v,"body")?)?; Value::Null },
        "mesh_send" => json!(runtime().block_on(mesh::mesh_send(id()?,string(&v,"host")?,integer(&v,"port")?.try_into().map_err(|_|"invalid port")?,string(&v,"device")?,string(&v,"body")?))?),
        "torrent_init" => { torrent::torrent_init_session(string(&v,"download_dir")?, Some(string(&v,"session_dir")?))?; Value::Null },
        "torrent_list" => json!(torrent::torrent_list(string(&v,"download_dir")?)?),
        "torrent_limits" => match torrent::bandwidth(v["download"].as_i64().ok_or("invalid download")?, v["upload"].as_i64().ok_or("invalid upload")?)? {
            Some((down, up)) => json!({"supported":true,"sessionInitialized":true,"applied":v["download"] != -1 || v["upload"] != -1,
                "actual":{"downloadBytesPerSecond":down,"uploadBytesPerSecond":up}}),
            None => json!({"supported":true,"sessionInitialized":false,"applied":false,"actual":null,"reason":"session_not_initialized"}),
        },
        "torrent_facts" => json!(torrent::torrent_download_facts(integer(&v,"id")?)?),
        "torrent_add_file" => json!(torrent::torrent_add_file(string(&v,"path")?,string(&v,"download_dir")?,v["create_folder"].as_bool().ok_or("invalid create_folder")?,file_indices()?)?),
        "torrent_begin_preview" => json!(torrent::torrent_begin_preview()?),
        "torrent_cancel_preview" => { torrent::torrent_cancel_preview(integer(&v,"request_id")?)?; Value::Null },
        "torrent_preview_magnet" => json!(torrent::torrent_preview_magnet(string(&v,"source")?,string(&v,"download_dir")?,integer(&v,"request_id")?)?),
        "torrent_add_magnet" => json!(torrent::torrent_add_magnet(string(&v,"source")?,string(&v,"download_dir")?,v["create_folder"].as_bool().ok_or("invalid create_folder")?,integer(&v,"request_id")?,file_indices()?)?),
        "torrent_select" => { torrent::torrent_select_files(integer(&v,"id")?,serde_json::from_value(v["indices"].clone()).map_err(|_|"invalid indices")?)?; Value::Null },
        "torrent_pause" => { torrent::torrent_pause(integer(&v,"id")?)?; Value::Null },
        "torrent_resume" => { torrent::torrent_resume(integer(&v,"id")?)?; Value::Null },
        "torrent_forget" => { torrent::torrent_forget(integer(&v,"id")?)?; Value::Null },
        _ => return Err("unsupported headless native operation".into()),
    };
    Ok(result)
}

/// Input/output are owned UTF-8 JSON. The caller frees output exactly once.
#[no_mangle]
pub unsafe extern "C" fn nipaplay_headless_call(input: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let text = CStr::from_ptr(input).to_str().map_err(|_| "invalid UTF-8".to_owned())?;
        let value = serde_json::from_str(text).map_err(|_| "invalid JSON".to_owned())?;
        dispatch(value)
    });
    let envelope = match result {
        Ok(Ok(v)) => json!({"result":v}),
        Ok(Err(e)) => json!({"error":e}),
        Err(_) => json!({"error":"headless native panic"}),
    };
    CString::new(envelope.to_string()).unwrap().into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn nipaplay_headless_free(value: *mut c_char) {
    drop(CString::from_raw(value));
}
