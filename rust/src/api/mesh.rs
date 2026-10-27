use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64, Engine as _};
use nipaplay_mesh::Node;
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU32, Ordering},
        Arc, Mutex, OnceLock,
    },
};

fn nodes() -> &'static Mutex<HashMap<u32, Arc<Node>>> {
    static NODES: OnceLock<Mutex<HashMap<u32, Arc<Node>>>> = OnceLock::new();
    NODES.get_or_init(|| Mutex::new(HashMap::new()))
}
fn node(id: u32) -> Result<Arc<Node>, String> {
    nodes()
        .lock()
        .unwrap()
        .get(&id)
        .cloned()
        .ok_or("mesh node stopped".into())
}
pub fn mesh_generate_key() -> Result<String, String> {
    Ok(B64.encode(nipaplay_mesh::generate_key()?))
}
pub fn mesh_public_key(private_key: String) -> Result<String, String> {
    Ok(B64.encode(nipaplay_mesh::public_key(
        &B64.decode(private_key).map_err(|e| e.to_string())?,
    )?))
}
pub fn mesh_sign(private_key: String, message: String) -> Result<String, String> {
    Ok(B64.encode(nipaplay_mesh::sign(
        &B64.decode(private_key).map_err(|e| e.to_string())?,
        message.as_bytes(),
    )?))
}
pub fn mesh_validate_certificate(
    ca: String,
    certificate: String,
    private_key: String,
    account: String,
) -> Result<String, String> {
    nipaplay_mesh::validate_local(
        &ca,
        &certificate,
        &B64.decode(private_key).map_err(|e| e.to_string())?,
        &account,
    )
}
pub async fn mesh_start(
    ca: String,
    certificate: String,
    private_key: String,
    account: String,
    allowed: Vec<String>,
    bind: String,
) -> Result<u32, String> {
    static NEXT: AtomicU32 = AtomicU32::new(1);
    let node = Node::start(
        ca,
        certificate,
        B64.decode(private_key).map_err(|e| e.to_string())?,
        account,
        allowed,
        bind,
    )
    .await?;
    let id = NEXT.fetch_add(1, Ordering::SeqCst);
    nodes().lock().unwrap().insert(id, node);
    Ok(id)
}
pub fn mesh_port(id: u32) -> Result<u16, String> {
    Ok(node(id)?.port)
}
pub fn mesh_update_devices(id: u32, allowed: Vec<String>) -> Result<(), String> {
    node(id)?.update_devices(allowed);
    Ok(())
}
pub fn mesh_stop(id: u32) -> Result<(), String> {
    let node = nodes()
        .lock()
        .unwrap()
        .remove(&id)
        .ok_or("mesh node stopped")?;
    node.stop();
    Ok(())
}
pub struct MeshIncoming {
    pub request_id: u64,
    pub device_id: String,
    pub body: String,
}
pub async fn mesh_next(id: u32) -> Result<MeshIncoming, String> {
    let event = node(id)?.next().await?;
    Ok(MeshIncoming {
        request_id: event.request_id,
        device_id: event.device_id,
        body: event.body,
    })
}
pub fn mesh_respond(id: u32, request_id: u64, body: String) -> Result<(), String> {
    let mut envelope: serde_json::Value = serde_json::from_str(&body).map_err(|e| e.to_string())?;
    let body = if let Some(file) = envelope["result"].get("_meshFile").cloned() {
        let path = file["path"].as_str().ok_or("missing library file")?;
        let offset = file["offset"].as_u64().ok_or("invalid offset")?;
        let length = file["length"].as_u64().filter(|n| *n <= nipaplay_mesh::MAX_FRAME as u64).ok_or("invalid length")?;
        envelope["result"].as_object_mut().unwrap().remove("_meshFile");
        format!("\0mesh-file\n{}\n{}\n{}\n{}", B64.encode(path), offset, length, envelope)
    } else { body };
    node(id)?.respond(request_id, body)
}
pub async fn mesh_send(
    id: u32,
    host: String,
    port: u16,
    device: String,
    body: String,
) -> Result<String, String> {
    // Only the read-only file primitive gets the media deadline. A task or a
    // write can legitimately run for much longer and must not be replayed.
    let file_read = serde_json::from_str::<serde_json::Value>(&body)
        .ok().is_some_and(|frame| frame["method"] == "mesh/library/read");
    let node = node(id)?;
    let response = if file_read {
        node.send_with_timeout(&host, port, &device, &body,
            std::time::Duration::from_secs(15)).await.map_err(|error| {
                if error == "call timeout" { "mesh file read timeout".to_owned() }
                else { error }
            })?
    } else {
        node.send(&host, port, &device, &body).await?
    };
    if let Some(bytes) = response.strip_prefix("\0mesh-bytes\n") {
        let (header, data) = bytes.split_once('\n').ok_or("invalid byte response")?;
        let mut envelope: serde_json::Value = serde_json::from_slice(&B64.decode(header).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
        envelope["result"]["data"] = data.into();
        Ok(envelope.to_string())
    } else { Ok(response) }
}
