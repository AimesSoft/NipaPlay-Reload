use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64, Engine as _};
use ring::{
    rand::SystemRandom,
    signature::{Ed25519KeyPair, KeyPair},
};
use rustls::{
    pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName},
    ClientConfig, RootCertStore, ServerConfig,
};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    io::Cursor,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex, RwLock,
    },
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::{mpsc, oneshot, watch, Semaphore},
    time::timeout,
};
use tokio_rustls::{TlsAcceptor, TlsConnector};

pub const MAX_FRAME: usize = 1024 * 1024;
const NETWORK_TIMEOUT: Duration = Duration::from_secs(10);
const CALL_TIMEOUT: Duration = Duration::from_secs(3600);

pub fn generate_key() -> Result<Vec<u8>, String> {
    Ed25519KeyPair::generate_pkcs8(&SystemRandom::new())
        .map(|k| k.as_ref().to_vec())
        .map_err(|e| e.to_string())
}
pub fn public_key(private: &[u8]) -> Result<Vec<u8>, String> {
    Ok(Ed25519KeyPair::from_pkcs8(private)
        .map_err(|e| e.to_string())?
        .public_key()
        .as_ref()
        .to_vec())
}
pub fn sign(private: &[u8], message: &[u8]) -> Result<Vec<u8>, String> {
    Ok(Ed25519KeyPair::from_pkcs8(private)
        .map_err(|e| e.to_string())?
        .sign(message)
        .as_ref()
        .to_vec())
}
pub fn device_id(public: &[u8]) -> String {
    B64.encode(Sha256::digest(public))
}

fn certificates(pem: &str) -> Result<Vec<CertificateDer<'static>>, String> {
    let certs = rustls_pemfile::certs(&mut Cursor::new(pem))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;
    if certs.is_empty() {
        return Err("empty certificate chain".into());
    }
    Ok(certs)
}

fn identity(cert: &CertificateDer<'_>) -> Result<(String, String), String> {
    let (_, parsed) =
        x509_parser::parse_x509_certificate(cert.as_ref()).map_err(|e| e.to_string())?;
    if !parsed.validity().is_valid() || parsed.is_ca() {
        return Err("invalid device certificate validity or CA flag".into());
    }
    let key = parsed.public_key();
    if key.algorithm.algorithm.to_id_string() != "1.3.101.112"
        || key.subject_public_key.data.len() != 32
    {
        return Err("device certificate must contain Ed25519 key".into());
    }
    let san = parsed
        .subject_alternative_name()
        .map_err(|e| e.to_string())?
        .ok_or("missing identity SAN")?;
    let uris: Vec<_> = san
        .value
        .general_names
        .iter()
        .filter_map(|n| {
            if let x509_parser::extensions::GeneralName::URI(uri) = n {
                Some(*uri)
            } else {
                None
            }
        })
        .collect();
    if uris.len() != 1 {
        return Err("ambiguous identity SAN".into());
    }
    let (account, device) = uris[0]
        .strip_prefix("nipaplay-mesh://device?account=")
        .and_then(|s| s.split_once("&device="))
        .ok_or("invalid identity SAN")?;
    if device_id(key.subject_public_key.data.as_ref()) != device {
        return Err("device id does not match public key".into());
    }
    Ok((account.into(), device.into()))
}

fn remaining_validity(cert: &CertificateDer<'_>) -> Result<Duration, String> {
    let (_, parsed) =
        x509_parser::parse_x509_certificate(cert.as_ref()).map_err(|e| e.to_string())?;
    let seconds: u64 = parsed
        .validity()
        .not_after
        .timestamp()
        .try_into()
        .map_err(|_| "invalid certificate expiry")?;
    let expiry = std::time::UNIX_EPOCH + Duration::from_secs(seconds);
    expiry
        .duration_since(std::time::SystemTime::now())
        .map_err(|_| "certificate expired".into())
}

pub fn validate_local(
    ca: &str,
    certificate: &str,
    private: &[u8],
    account: &str,
) -> Result<String, String> {
    let leaf = certificates(certificate)?;
    let (owner, device) = identity(&leaf[0])?;
    if owner != account || device != device_id(&public_key(private)?) {
        return Err("local identity mismatch".into());
    }
    let client = client_config(ca, certificate, private)?;
    use rustls::client::danger::ServerCertVerifier;
    let verifier = rustls::client::WebPkiServerVerifier::builder_with_provider(
        Arc::new(roots(ca)?),
        provider(),
    )
    .build()
    .map_err(|e| e.to_string())?;
    verifier
        .verify_server_cert(
            &leaf[0],
            &leaf[1..],
            &server_name(&device)?,
            &[],
            rustls::pki_types::UnixTime::now(),
        )
        .map_err(|e| e.to_string())?;
    drop(client);
    Ok(device)
}
fn roots(ca: &str) -> Result<RootCertStore, String> {
    let mut roots = RootCertStore::empty();
    for cert in certificates(ca)? {
        roots.add(cert).map_err(|e| e.to_string())?;
    }
    Ok(roots)
}
fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}
fn private_key(private: &[u8]) -> PrivateKeyDer<'static> {
    PrivatePkcs8KeyDer::from(private.to_vec()).into()
}
fn client_config(ca: &str, cert: &str, private: &[u8]) -> Result<ClientConfig, String> {
    ClientConfig::builder_with_provider(provider())
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(|e| e.to_string())?
        .with_root_certificates(roots(ca)?)
        .with_client_auth_cert(certificates(cert)?, private_key(private))
        .map_err(|e| e.to_string())
}
fn server_name(device: &str) -> Result<ServerName<'static>, String> {
    ServerName::try_from(device_dns_name(device)?).map_err(|e| e.to_string())
}

pub fn device_dns_name(device: &str) -> Result<String, String> {
    let hash = B64.decode(device).map_err(|_| "invalid device id")?;
    if hash.len() != 32 {
        return Err("invalid device id length".into());
    }
    let hex = hash
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    Ok(format!(
        "d-{}.{}.mesh.nipaplay.invalid",
        &hex[..32],
        &hex[32..]
    ))
}

pub struct Incoming {
    pub request_id: u64,
    pub device_id: String,
    pub body: String,
}
struct Request {
    incoming: Incoming,
    response: oneshot::Sender<String>,
}
pub struct Node {
    pub port: u16,
    pub device_id: String,
    account: String,
    allowed: RwLock<HashSet<String>>,
    changes: watch::Sender<u64>,
    client: Arc<ClientConfig>,
    events: tokio::sync::Mutex<mpsc::Receiver<Request>>,
    responses: Mutex<HashMap<u64, oneshot::Sender<String>>>,
    listener: Mutex<Option<tokio::task::JoinHandle<()>>>,
    stopped: std::sync::atomic::AtomicBool,
}

impl Node {
    pub async fn start(
        ca: String,
        certificate: String,
        private: Vec<u8>,
        account: String,
        allowed: Vec<String>,
        bind: String,
    ) -> Result<Arc<Self>, String> {
        let device = validate_local(&ca, &certificate, &private, &account)?;
        let verifier = rustls::server::WebPkiClientVerifier::builder_with_provider(
            Arc::new(roots(&ca)?),
            provider(),
        )
        .build()
        .map_err(|e| e.to_string())?;
        let server = ServerConfig::builder_with_provider(provider())
            .with_protocol_versions(&[&rustls::version::TLS13])
            .map_err(|e| e.to_string())?
            .with_client_cert_verifier(verifier)
            .with_single_cert(certificates(&certificate)?, private_key(&private))
            .map_err(|e| e.to_string())?;
        let client = Arc::new(client_config(&ca, &certificate, &private)?);
        let listener = TcpListener::bind(bind).await.map_err(|e| e.to_string())?;
        let port = listener.local_addr().map_err(|e| e.to_string())?.port();
        let (events_tx, events_rx) = mpsc::channel(64);
        let (changes, _) = watch::channel(0);
        let node = Arc::new(Self {
            port,
            device_id: device,
            account,
            allowed: RwLock::new(allowed.into_iter().collect()),
            changes,
            client,
            events: tokio::sync::Mutex::new(events_rx),
            responses: Mutex::new(HashMap::new()),
            listener: Mutex::new(None),
            stopped: std::sync::atomic::AtomicBool::new(false),
        });
        let weak = Arc::downgrade(&node);
        let acceptor = TlsAcceptor::from(Arc::new(server));
        let slots = Arc::new(Semaphore::new(64));
        let task = tokio::spawn(async move {
            while let Ok((tcp, _)) = listener.accept().await {
                let Ok(permit) = slots.clone().try_acquire_owned() else {
                    continue;
                };
                let Some(node) = weak.upgrade() else { break };
                let acceptor = acceptor.clone();
                let tx = events_tx.clone();
                tokio::spawn(async move {
                    let _permit = permit;
                    // A refused peer gets EOF; its request never reaches the Harness.
                    if let Err(error) = node.receive(tcp, acceptor, tx).await {
                        eprintln!("mesh connection rejected: {error}");
                    }
                });
            }
        });
        *node.listener.lock().unwrap() = Some(task);
        Ok(node)
    }
    fn check_identity(&self, cert: &CertificateDer<'_>, expected: Option<&str>) -> Result<String, String> {
        let (account, device) = identity(cert)?;
        if account != self.account {
            return Err("account mismatch".into());
        }
        if expected.is_some_and(|id| id != device) {
            return Err("unexpected device".into());
        }
        Ok(device)
    }
    fn check(&self, cert: &CertificateDer<'_>, expected: Option<&str>) -> Result<String, String> {
        let device = self.check_identity(cert, expected)?;
        self.check_device(&device)?;
        Ok(device)
    }
    fn check_device(&self, device: &str) -> Result<(), String> {
        let allowed = self.allowed.read().unwrap();
        if self.stopped.load(Ordering::SeqCst)
            || !allowed.contains(device)
            || !allowed.contains(&self.device_id)
        {
            return Err("device revoked or not registered".into());
        }
        Ok(())
    }
    pub fn update_devices(&self, allowed: Vec<String>) {
        *self.allowed.write().unwrap() = allowed.into_iter().collect();
        self.changes.send_modify(|version| *version += 1);
    }
    pub fn stop(&self) {
        self.stopped.store(true, Ordering::SeqCst);
        if let Some(task) = self.listener.lock().unwrap().take() {
            task.abort();
        }
        self.responses.lock().unwrap().clear();
        self.changes.send_modify(|version| *version += 1);
    }
    async fn cancelled(&self, device: &str, mut changes: watch::Receiver<u64>) {
        loop {
            if self.check_device(device).is_err() {
                return;
            }
            if changes.changed().await.is_err() {
                return;
            }
        }
    }
    async fn receive(
        &self,
        tcp: TcpStream,
        acceptor: TlsAcceptor,
        tx: mpsc::Sender<Request>,
    ) -> Result<(), String> {
        let changes = self.changes.subscribe();
        let mut tls = timeout(NETWORK_TIMEOUT, acceptor.accept(tcp))
            .await
            .map_err(|_| "TLS handshake timeout")?
            .map_err(|e| e.to_string())?;
        let peer_expiry = remaining_validity(
            &tls.get_ref()
                .1
                .peer_certificates()
                .ok_or("missing peer certificate")?[0],
        )?;
        let peer = self.check_identity(
            &tls.get_ref()
                .1
                .peer_certificates()
                .ok_or("missing peer certificate")?[0],
            None,
        )?;
        if self.check_device(&peer).is_err() {
            if self.stopped.load(Ordering::SeqCst)
                || !self.allowed.read().unwrap().contains(&self.device_id)
            {
                return Err("device revoked or not registered".into());
            }
            static VERIFY_SEQ: AtomicU64 = AtomicU64::new(1 << 62);
            let verify_id = VERIFY_SEQ.fetch_add(1, Ordering::SeqCst);
            let (send, receive) = oneshot::channel();
            if tx
                .send(Request {
                    incoming: Incoming {
                        request_id: verify_id,
                        device_id: peer.clone(),
                        body: "\0mesh-verify-peer".into(),
                    },
                    response: send,
                })
                .await
                .is_ok()
            {
                let _ = timeout(NETWORK_TIMEOUT, receive).await;
            }
            self.check_device(&peer)?;
        }
        tokio::select! {
            _ = tokio::time::sleep(peer_expiry) => Err("peer certificate expired".into()),
            _ = self.cancelled(&peer, changes) => Err("device revoked".into()),
            result = timeout(CALL_TIMEOUT, async {
                let body = timeout(NETWORK_TIMEOUT, read_frame(&mut tls)).await.map_err(|_| "request timeout")??;
                static SEQUENCE: AtomicU64 = AtomicU64::new(1);
                let id = SEQUENCE.fetch_add(1, Ordering::SeqCst);
                let (send, receive) = oneshot::channel();
                tx.send(Request { incoming: Incoming { request_id: id, device_id: peer.clone(), body }, response: send }).await.map_err(|_| "node stopped")?;
                let response = receive.await.map_err(|_| "response cancelled")?;
                self.check_device(&peer)?;
                if let Some(spec) = response.strip_prefix("\0mesh-file\n") {
                    let parts: Vec<_> = spec.splitn(4, '\n').collect();
                    if parts.len() != 4 { return Err("invalid file response".into()); }
                    let path = String::from_utf8(B64.decode(parts[0]).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
                    let offset = parts[1].parse::<u64>().map_err(|e| e.to_string())?;
                    let count = parts[2].parse::<usize>().map_err(|e| e.to_string())?;
                    let header = parts[3].as_bytes();
                    if count > MAX_FRAME || header.len() > MAX_FRAME { return Err("byte response too large".into()); }
                    let bytes = tokio::task::spawn_blocking(move || -> Result<Vec<u8>, String> {
                        use std::io::{Read, Seek};
                        let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
                        file.seek(std::io::SeekFrom::Start(offset)).map_err(|e| e.to_string())?;
                        let mut bytes = vec![0; count];
                        file.read_exact(&mut bytes).map_err(|e| e.to_string())?;
                        Ok(bytes)
                    }).await.map_err(|e| e.to_string())??;
                    tls.write_u32(0x80000000 | header.len() as u32).await.map_err(|e| e.to_string())?;
                    tls.write_all(header).await.map_err(|e| e.to_string())?;
                    tls.write_u32(bytes.len() as u32).await.map_err(|e| e.to_string())?;
                    tls.write_all(&bytes).await.map_err(|e| e.to_string())?;
                } else {
                    write_frame(&mut tls, &response).await?;
                }
                tls.shutdown().await.map_err(|e| e.to_string())
            }) => result.map_err(|_| "call timeout".to_owned())?,
        }
    }
    pub async fn next(&self) -> Result<Incoming, String> {
        let changes = self.changes.subscribe();
        let mut events = self.events.lock().await;
        let request = tokio::select! {
            _ = self.cancelled(&self.device_id, changes) => return Err("node stopped".into()),
            event = events.recv() => event.ok_or("node stopped")?,
        };
        self.responses
            .lock()
            .unwrap()
            .insert(request.incoming.request_id, request.response);
        Ok(request.incoming)
    }
    pub fn respond(&self, id: u64, body: String) -> Result<(), String> {
        let send = self
            .responses
            .lock()
            .unwrap()
            .remove(&id)
            .ok_or("request no longer active")?;
        send.send(body).map_err(|_| "peer disconnected".into())
    }
    pub async fn send(
        &self,
        host: &str,
        port: u16,
        device: &str,
        body: &str,
    ) -> Result<String, String> {
        self.check_device(device)?;
        let changes = self.changes.subscribe();
        tokio::select! {
            _ = self.cancelled(device, changes) => Err("device revoked".into()),
            result = timeout(CALL_TIMEOUT, async {
                let tcp = timeout(NETWORK_TIMEOUT, TcpStream::connect((host, port))).await.map_err(|_| "connect: connect timeout".to_owned())?.map_err(|e| format!("connect: {e}"))?;
                let mut tls = timeout(NETWORK_TIMEOUT, TlsConnector::from(self.client.clone()).connect(server_name(device).map_err(|e| format!("connect: {e}"))?, tcp)).await.map_err(|_| "connect: TLS handshake timeout".to_owned())?.map_err(|e| format!("connect: {e}"))?;
                let peer_certs = tls.get_ref().1.peer_certificates().ok_or_else(|| "connect: missing peer certificate".to_owned())?;
                self.check(&peer_certs[0], Some(device)).map_err(|e| format!("connect: {e}"))?;
                let peer_expiry = remaining_validity(&peer_certs[0]).map_err(|e| format!("connect: {e}"))?;
                write_frame(&mut tls, body).await?;
                tokio::select! {
                    _ = tokio::time::sleep(peer_expiry) => Err("peer certificate expired".into()),
                    response = async {
                        let size = tls.read_u32().await.map_err(|e| e.to_string())?;
                        let binary = size & 0x80000000 != 0;
                        let size = (size & 0x7fffffff) as usize;
                        if size == 0 || size > MAX_FRAME { return Err("invalid response frame".into()); }
                        let mut header = vec![0; size];
                        tls.read_exact(&mut header).await.map_err(|e| e.to_string())?;
                        if !binary { return String::from_utf8(header).map_err(|e| e.to_string()); }
                        let count = tls.read_u32().await.map_err(|e| e.to_string())? as usize;
                        if count > MAX_FRAME { return Err("invalid byte response length".into()); }
                        let mut bytes = vec![0; count];
                        tls.read_exact(&mut bytes).await.map_err(|e| e.to_string())?;
                        Ok(format!("\0mesh-bytes\n{}\n{}", B64.encode(header), base64::engine::general_purpose::STANDARD.encode(bytes)))
                    } => response,
                }
            }) => result.map_err(|_| "call timeout".to_owned())?,
        }
    }
}
async fn read_frame<S: AsyncRead + Unpin>(socket: &mut S) -> Result<String, String> {
    let size = socket.read_u32().await.map_err(|e| e.to_string())? as usize;
    if size == 0 || size > MAX_FRAME {
        return Err("invalid frame size".into());
    }
    let mut bytes = vec![0; size];
    socket
        .read_exact(&mut bytes)
        .await
        .map_err(|e| e.to_string())?;
    String::from_utf8(bytes).map_err(|_| "invalid UTF-8 frame".into())
}
async fn write_frame<S: AsyncWrite + Unpin>(socket: &mut S, body: &str) -> Result<(), String> {
    if body.is_empty() || body.len() > MAX_FRAME {
        return Err("invalid frame size".into());
    }
    socket
        .write_u32(body.len() as u32)
        .await
        .map_err(|e| e.to_string())?;
    socket
        .write_all(body.as_bytes())
        .await
        .map_err(|e| e.to_string())?;
    socket.flush().await.map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_base64url_device_id_prefix_is_accepted_by_the_standard_dns_validator() {
        for first in 0..=255 {
            let mut hash = [0xff; 32];
            hash[0] = first;
            let device = B64.encode(hash);
            assert!(
                server_name(&device).is_ok(),
                "DNS binding must work for {device}"
            );
        }
    }
    #[tokio::test]
    async fn send_to_unreachable_port_reports_connect_stage_prefix() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let unused_port = listener.local_addr().unwrap().port();
        drop(listener);
        let result = timeout(
            NETWORK_TIMEOUT,
            TcpStream::connect(("127.0.0.1", unused_port)),
        )
        .await
        .map_err(|_| "connect: connect timeout".to_owned())
        .and_then(|r| r.map_err(|e| format!("connect: {e}")));
        let err = result.unwrap_err();
        assert!(err.starts_with("connect:"), "expected connect: prefix, got {err}");
    }
}
