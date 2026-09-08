use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr};

use socket2::SockRef;

use crate::{Error, bind_device::BindDevice};

#[derive(Clone, Copy, Debug, Default)]
pub struct ConnectOpts<'a> {
    pub source_port: Option<u16>,
    pub bind_device: Option<&'a BindDevice>,
}

pub async fn tcp_connect<'a>(
    addr: SocketAddr,
    opts: ConnectOpts<'a>,
) -> crate::Result<tokio::net::TcpStream> {
    let (sock, bind_addr) = if addr.is_ipv6() {
        (
            tokio::net::TcpSocket::new_v6().map_err(Error::SocketNew)?,
            SocketAddr::from((Ipv6Addr::UNSPECIFIED, opts.source_port.unwrap_or(0))),
        )
    } else {
        (
            tokio::net::TcpSocket::new_v4().map_err(Error::SocketNew)?,
            SocketAddr::from((Ipv4Addr::UNSPECIFIED, opts.source_port.unwrap_or(0))),
        )
    };
    let sref = SockRef::from(&sock);

    if let Some(bd) = opts.bind_device {
        bd.bind_sref(&sref, addr.is_ipv6())?;
    }

    if bind_addr.port() > 0 {
        #[cfg(not(windows))]
        sref.set_reuse_port(true).map_err(Error::ReusePort)?;
        sref.set_reuse_address(true).map_err(Error::ReuseAddress)?;
        sref.bind(&bind_addr.into()).map_err(Error::Bind)?;
    }

    sock.connect(addr).await.map_err(Error::Connect)
}
