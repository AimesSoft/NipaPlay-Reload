#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("error taking ownership of a socket from a file descriptor: {0}")]
    SocketFromFd(std::io::Error),
    #[error("error creating socket: {0}")]
    SocketNew(std::io::Error),
    #[error("error binding: {0}")]
    Bind(std::io::Error),
    #[error("error setting only_v6={value}: {source}")]
    OnlyV6 { value: bool, source: std::io::Error },
    #[error("error setting SO_REUSEADDR: {0}")]
    ReuseAddress(std::io::Error),
    #[error("error getting local_addr(): {0}")]
    LocalAddr(std::io::Error),
    #[error("as_socket() returned None")]
    AsSocket,
    #[error("error setting nonblocking=true: {0}")]
    SetNonblocking(std::io::Error),
    #[error("mismatch between local_addr and requested bind_addr")]
    LocalBindAddrMismatch,
    #[error("error listening")]
    Listen(std::io::Error),
    #[error("error calling tokio from_std")]
    TokioFromStd(std::io::Error),
    #[error("did not join any multicast groups")]
    MulticastJoinFail,
    #[error("provided link-local address is not link-local")]
    ProvidedLinkLocalAddrIsntLinkLocal,
    #[error("no network interfaces found")]
    NoNics,
    #[error("provided site-local address is not site-local")]
    ProvidedSiteLocalAddrIsNotSiteLocal,
    #[error("error setting SO_REUSEPORT")]
    ReusePort(std::io::Error),
    #[error("error waiting for socket to become writeable")]
    Writeable(std::io::Error),
    #[error("error calling set_multicast_if_v6")]
    SetMulticastIpv6(std::io::Error),
    #[error("error calling set_multicast_if_v4")]
    SetMulticastIpv4(std::io::Error),
    #[error("send_multicast_msg called with conflicting parameters")]
    SendMulticastMsgProtocolMismatch,
    #[error("error sending: {0:#}")]
    Send(std::io::Error),
    #[error("binding to device is not supported on your OS")]
    BindDeviceNotSupported,
    #[error("invalid bind device")]
    BindDeviceInvalid,
    #[error("invalid bind device: {0:#}")]
    BindDeviceInvalidError(std::io::Error),
    #[error("error setting bind device: {0:#}")]
    BindDeviceSetDeviceError(std::io::Error),
    #[error("error connecting: {0:#}")]
    Connect(std::io::Error),
}

pub type Result<T> = core::result::Result<T, Error>;
