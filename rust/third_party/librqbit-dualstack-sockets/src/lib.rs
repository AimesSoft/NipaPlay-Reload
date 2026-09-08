#[cfg(test)]
mod tests;

mod bind_device;
mod connect;
mod error;
mod multicast;
mod traits;
pub use error::{Error, Result};

use crate::socket::MaybeDualstackSocket;

pub mod addr;
pub mod socket;

pub type TcpListener = MaybeDualstackSocket<tokio::net::TcpListener>;
pub type UdpSocket = MaybeDualstackSocket<tokio::net::UdpSocket>;
pub use bind_device::BindDevice;
pub use connect::{ConnectOpts, tcp_connect};
pub use multicast::{MulticastOpts, MulticastUdpSocket};
pub use socket::BindOpts;
pub use traits::PollSendToVectored;

#[cfg(feature = "axum")]
pub use socket::axum::WrappedSocketAddr;
