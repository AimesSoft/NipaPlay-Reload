use std::{
    net::{Ipv4Addr, Ipv6Addr, SocketAddrV4, SocketAddrV6},
    time::Duration,
};

use bstr::BStr;
use tokio::time::timeout;
use tracing::trace;

use crate::{BindDevice, MulticastUdpSocket};

async fn bind_mcast_sock(port: u16, bd_name: Option<&str>) -> MulticastUdpSocket {
    let bd = bd_name.map(|name| BindDevice::new_from_name(name).unwrap());
    MulticastUdpSocket::new(
        (Ipv6Addr::UNSPECIFIED, port).into(),
        SocketAddrV4::new(Ipv4Addr::new(239, 255, 255, 250), port),
        SocketAddrV6::new(Ipv6Addr::new(0xff05, 0, 0, 0, 0, 0, 0, 0xc), port, 0, 0),
        Some(SocketAddrV6::new(
            Ipv6Addr::new(0xff02, 0, 0, 0, 0, 0, 0, 0xc),
            port,
            0,
            0,
        )),
        bd.as_ref(),
    )
    .await
    .unwrap()
}

pub fn setup_test_logging() {
    unsafe { std::env::set_var("RUST_BACKTRACE", "1") };
    if std::env::var("RUST_LOG").is_err() {
        unsafe { std::env::set_var("RUST_LOG", "trace") };
    }
    let _ = tracing_subscriber::fmt::try_init();
}

#[tokio::test]
async fn multicast_example() {
    setup_test_logging();
    let sock = bind_mcast_sock(1901, None).await;

    let recv = async {
        let mut buf = [0u8; 256];
        while let Ok(()) = tokio::time::timeout(Duration::from_millis(100), async {
            let (payload, addr) = sock.recv_from(&mut buf).await.unwrap();
            let payload = BStr::new(&buf[..payload]);
            let reply_opts = sock.find_mcast_opts_for_replying_to(&addr);
            println!("received from {addr:?}; reply_opts={reply_opts:?}, payload={payload:?}");
        })
        .await
        {}

        trace!("recv timed out")
    };

    let send = sock.try_send_mcast_everywhere(&|mopts| format!("{mopts:?}").into());

    tokio::join!(recv, send);
}

#[test]
fn test_is_ula() {
    let addr: Ipv6Addr = "fd65:51cb:c099:0:183e:9c41:ed06:235".parse().unwrap();
    let addr2: Ipv6Addr = "204:6b7e:3cd7:3447:64db:aecf:d9ce:65f".parse().unwrap();
    assert!(addr.is_unique_local());
    assert!(!addr2.is_unique_local());

    let mask: u128 = 0xffffffff00000000;
    assert!(addr.to_bits() & mask != addr2.to_bits() & mask)
}

#[tokio::test]
async fn test_v4_received() {
    setup_test_logging();
    let sock = bind_mcast_sock(1902, None).await;

    sock.try_send_mcast_everywhere(&|opts| {
        if opts.iface_ip().is_ipv4() {
            Some("hello".into())
        } else {
            None
        }
    })
    .await;

    let mut buf = [0u8; 5];
    let (sz, addr) = timeout(Duration::from_millis(100), sock.recv_from(&mut buf))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sz, 5);
    assert!(addr.is_ipv4(), "{addr:?} expected v4");
    assert_eq!(&buf, b"hello");
}

#[tokio::test]
async fn test_v6_received() {
    setup_test_logging();
    let sock = bind_mcast_sock(1903, None).await;

    sock.try_send_mcast_everywhere(&|opts| {
        if opts.iface_ip().is_ipv6() {
            Some("hello".into())
        } else {
            None
        }
    })
    .await;

    let mut buf = [0u8; 5];
    let (sz, addr) = timeout(Duration::from_millis(100), sock.recv_from(&mut buf))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sz, 5);
    assert!(addr.is_ipv6(), "{addr:?} expected v6");
    assert_eq!(&buf, b"hello");
}

#[tokio::test]
async fn bind_multiple_same_port() {
    setup_test_logging();
    let sock1 = bind_mcast_sock(1904, None).await;
    let sock2 = bind_mcast_sock(1904, None).await;

    sock1
        .try_send_mcast_everywhere(&|opts| {
            if opts.iface_ip().is_ipv4() {
                Some("hello".into())
            } else {
                None
            }
        })
        .await;
    sock2
        .try_send_mcast_everywhere(&|opts| {
            if opts.iface_ip().is_ipv4() {
                Some("hello".into())
            } else {
                None
            }
        })
        .await;

    let mut buf = [0u8; 5];
    let (sz, addr) = timeout(Duration::from_millis(100), sock1.recv_from(&mut buf))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sz, 5);
    assert!(addr.is_ipv4(), "{addr:?} expected v4");
    assert_eq!(&buf, b"hello");

    let (sz, addr) = timeout(Duration::from_millis(100), sock2.recv_from(&mut buf))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sz, 5);
    assert!(addr.is_ipv4(), "{addr:?} expected v4");
    assert_eq!(&buf, b"hello");
}

#[cfg(not(windows))]
#[tokio::test]
async fn test_mcast_bind_device() {
    use crate::bind_device::tests::find_localhost_name;

    setup_test_logging();

    let lo = find_localhost_name();

    let sock = bind_mcast_sock(1905, Some(&lo)).await;

    sock.try_send_mcast_everywhere(&|_| Some("hello".into()))
        .await;

    let mut buf = [0u8; 5];
    let (sz, addr) = timeout(Duration::from_millis(100), sock.recv_from(&mut buf))
        .await
        .unwrap()
        .unwrap();
    trace!(?addr, sz, "received");
    assert_eq!(sz, 5);
    assert_eq!(&buf, b"hello");
}
