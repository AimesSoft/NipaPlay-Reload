use crate::BindOpts;
use crate::TcpListener;
use crate::UdpSocket;

use anyhow::Context;
use std::net::Ipv4Addr;
use std::net::{IpAddr, Ipv6Addr, SocketAddr};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::timeout;
use tracing::level_filters::LevelFilter;
use tracing::trace;
use tracing_subscriber::EnvFilter;

const TIMEOUT: Duration = Duration::from_secs(100);

fn ipv4_localhost() -> SocketAddr {
    (Ipv4Addr::LOCALHOST, 0).into()
}

fn ipv6_localhost() -> SocketAddr {
    (Ipv6Addr::LOCALHOST, 0).into()
}

fn ipv6_unspecified() -> SocketAddr {
    (Ipv6Addr::UNSPECIFIED, 0).into()
}

// For both TCP and UDP:
// - spin up two IPv6 dualstack sockets.
//   Assert that sending to both localhost IPv4 and localhost IPv6 works, and the address received in accept matches the protocol.
// - pure IPv6 - test that it works
// - pure IPv4 - test that it works

struct BindSpec {
    addr: SocketAddr,
    request_dualstack: bool,
    expect_dualstack: bool,
}

impl BindSpec {
    fn bind_tcp(&self) -> TcpListener {
        let res = TcpListener::bind_tcp(
            self.addr,
            BindOpts {
                request_dualstack: self.request_dualstack,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(res.is_dualstack(), self.expect_dualstack);
        res
    }

    fn bind_udp(&self) -> UdpSocket {
        let res = UdpSocket::bind_udp(
            self.addr,
            BindOpts {
                request_dualstack: self.request_dualstack,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(res.is_dualstack(), self.expect_dualstack);
        res
    }
}

#[derive(Clone, Copy)]
enum SendSpec {
    SendToV4,
    SendToV6,
}

#[derive(Clone, Copy)]
struct SendAssertion {
    spec: SendSpec,
    should_work: bool,
}

fn setup_test_logging() {
    let _ = tracing_subscriber::fmt::Subscriber::builder()
        .with_env_filter(
            EnvFilter::builder()
                .with_default_directive(LevelFilter::TRACE.into())
                .from_env()
                .unwrap(),
        )
        .try_init();
    unsafe { std::env::set_var("RUST_BACKTRACE", "1") }
}

async fn test_tcp(server: BindSpec, tests: &[SendAssertion]) {
    for test in tests.iter().copied() {
        let server = server.bind_tcp();

        let remote = match test.spec {
            SendSpec::SendToV4 => {
                SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), server.bind_addr().port())
            }
            SendSpec::SendToV6 => {
                SocketAddr::new(IpAddr::V6(Ipv6Addr::LOCALHOST), server.bind_addr().port())
            }
        };

        let f1 = async {
            if !test.should_work {
                return;
            }
            let (mut stream, addr) = timeout(TIMEOUT, server.accept())
                .await
                .context("timeout accepting")
                .unwrap()
                .context("error accepting")
                .unwrap();
            trace!(?addr, "accepted");
            match test.spec {
                SendSpec::SendToV4 => {
                    assert!(addr.is_ipv4())
                }
                SendSpec::SendToV6 => {
                    assert!(addr.is_ipv6())
                }
            };

            assert_eq!(stream.read_u32().await.unwrap(), 42);
        };

        let f2 = async {
            let res = timeout(TIMEOUT, tokio::net::TcpStream::connect(remote))
                .await
                .with_context(|| format!("timeout connecting to {remote}"))
                .unwrap();
            let mut stream = if test.should_work {
                res.with_context(|| format!("error connecting to {remote}"))
                    .unwrap()
            } else {
                return;
            };
            trace!(?remote, "connected");
            stream.write_u32(42).await.unwrap();
        };

        tokio::join!(f1, f2);
    }
}

async fn test_udp(server1: BindSpec, server2: BindSpec, tests: &[SendAssertion]) {
    for test in tests.iter().copied() {
        let server1 = server1.bind_udp();
        let server2 = server2.bind_udp();

        let remote = match test.spec {
            SendSpec::SendToV4 => {
                SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), server2.bind_addr().port())
            }
            SendSpec::SendToV6 => {
                SocketAddr::new(IpAddr::V6(Ipv6Addr::LOCALHOST), server2.bind_addr().port())
            }
        };

        let f1 = async {
            if !test.should_work {
                return;
            }
            let mut buf = [0u8; 4];
            let (size, addr) = timeout(TIMEOUT, server2.recv_from(&mut buf))
                .await
                .context("timeout receiving")
                .unwrap()
                .context("error receiving")
                .unwrap();
            assert_eq!(size, 4);
            trace!(?addr, "received");
            match test.spec {
                SendSpec::SendToV4 => {
                    assert!(addr.is_ipv4())
                }
                SendSpec::SendToV6 => {
                    assert!(addr.is_ipv6())
                }
            };

            assert_eq!(u32::from_le_bytes(buf), 42);
        };

        let f2 = async {
            let buf = 42u32.to_le_bytes();
            trace!(server_bind_addr=?server1.bind_addr(), ?remote, "sending");
            let res = timeout(TIMEOUT, server1.send_to(&buf, remote))
                .await
                .with_context(|| format!("timeout sending to {remote}"))
                .unwrap();
            if test.should_work {
                res.with_context(|| format!("error sending to {remote}"))
                    .unwrap();
            } else {
                assert!(res.is_err())
            }
        };

        tokio::join!(f1, f2);
    }
}

#[tokio::test]
async fn test_tcp_ipv6_unspecified_dualstack() {
    setup_test_logging();
    test_tcp(
        BindSpec {
            addr: ipv6_unspecified(),
            request_dualstack: true,
            expect_dualstack: true,
        },
        &[
            SendAssertion {
                spec: SendSpec::SendToV6,
                should_work: true,
            },
            SendAssertion {
                spec: SendSpec::SendToV4,
                should_work: true,
            },
        ],
    )
    .await
}

#[tokio::test]
async fn test_tcp_ipv6_unspecified_no_dualstack() {
    setup_test_logging();
    test_tcp(
        BindSpec {
            addr: ipv6_unspecified(),
            request_dualstack: false,
            expect_dualstack: false,
        },
        &[
            SendAssertion {
                spec: SendSpec::SendToV6,
                should_work: true,
            },
            SendAssertion {
                spec: SendSpec::SendToV4,
                should_work: false,
            },
        ],
    )
    .await
}

#[tokio::test]
async fn test_tcp_ipv6_localhost() {
    setup_test_logging();
    test_tcp(
        BindSpec {
            addr: ipv6_localhost(),
            request_dualstack: true,
            expect_dualstack: false,
        },
        &[
            SendAssertion {
                spec: SendSpec::SendToV6,
                should_work: true,
            },
            SendAssertion {
                spec: SendSpec::SendToV4,
                should_work: false,
            },
        ],
    )
    .await
}

#[tokio::test]
async fn test_tcp_ipv4_localhost() {
    setup_test_logging();
    test_tcp(
        BindSpec {
            addr: ipv4_localhost(),
            request_dualstack: true,
            expect_dualstack: false,
        },
        &[
            SendAssertion {
                spec: SendSpec::SendToV6,
                should_work: false,
            },
            SendAssertion {
                spec: SendSpec::SendToV4,
                should_work: true,
            },
        ],
    )
    .await
}

#[tokio::test]
async fn test_udp_ipv6_unspecified_dualstack() {
    setup_test_logging();
    test_udp(
        BindSpec {
            addr: ipv6_unspecified(),
            request_dualstack: true,
            expect_dualstack: true,
        },
        BindSpec {
            addr: ipv6_unspecified(),
            request_dualstack: true,
            expect_dualstack: true,
        },
        &[
            SendAssertion {
                spec: SendSpec::SendToV6,
                should_work: true,
            },
            SendAssertion {
                spec: SendSpec::SendToV4,
                should_work: true,
            },
        ],
    )
    .await
}

#[tokio::test]
async fn test_udp_ipv6_unspecified_no_dualstack() {
    setup_test_logging();
    test_udp(
        BindSpec {
            addr: ipv6_unspecified(),
            request_dualstack: false,
            expect_dualstack: false,
        },
        BindSpec {
            addr: ipv6_unspecified(),
            request_dualstack: false,
            expect_dualstack: false,
        },
        &[
            SendAssertion {
                spec: SendSpec::SendToV6,
                should_work: true,
            },
            SendAssertion {
                spec: SendSpec::SendToV4,
                should_work: false,
            },
        ],
    )
    .await
}

#[tokio::test]
async fn test_udp_ipv6_localhost() {
    setup_test_logging();
    test_udp(
        BindSpec {
            addr: ipv6_localhost(),
            request_dualstack: true,
            expect_dualstack: false,
        },
        BindSpec {
            addr: ipv6_localhost(),
            request_dualstack: false,
            expect_dualstack: false,
        },
        &[
            SendAssertion {
                spec: SendSpec::SendToV6,
                should_work: true,
            },
            SendAssertion {
                spec: SendSpec::SendToV4,
                should_work: false,
            },
        ],
    )
    .await
}

#[tokio::test]
async fn test_udp_ipv4_localhost() {
    setup_test_logging();
    test_udp(
        BindSpec {
            addr: ipv4_localhost(),
            request_dualstack: true,
            expect_dualstack: false,
        },
        BindSpec {
            addr: ipv4_localhost(),
            request_dualstack: true,
            expect_dualstack: false,
        },
        &[
            SendAssertion {
                spec: SendSpec::SendToV6,
                should_work: false,
            },
            SendAssertion {
                spec: SendSpec::SendToV4,
                should_work: true,
            },
        ],
    )
    .await
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn test_tcp_from_fd_dualstack() {
    setup_test_logging();

    use std::os::fd::OwnedFd;
    let listener = std::net::TcpListener::bind("[::]:0").unwrap();
    let fd: OwnedFd = listener.into();
    let sock: TcpListener = fd.try_into().unwrap();
    assert!(sock.is_dualstack());
    assert!(sock.bind_addr().is_ipv6());
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn test_tcp_from_fd_v6_only() {
    setup_test_logging();

    use std::os::fd::OwnedFd;
    let listener = std::net::TcpListener::bind("[::1]:0").unwrap();
    let fd: OwnedFd = listener.into();
    let sock: TcpListener = fd.try_into().unwrap();
    assert!(!sock.is_dualstack());
    assert!(sock.bind_addr().is_ipv6());
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn test_tcp_from_fd_v4_only() {
    setup_test_logging();

    use std::os::fd::OwnedFd;
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let fd: OwnedFd = listener.into();
    let sock: TcpListener = fd.try_into().unwrap();
    assert!(!sock.is_dualstack());
    assert!(sock.bind_addr().is_ipv4());
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn test_tcp_from_fd_wrong_socket() {
    setup_test_logging();

    use std::os::fd::OwnedFd;
    let udp_socket = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
    let fd: OwnedFd = udp_socket.into();
    assert!(
        TcpListener::try_from(fd).is_err(),
        "should not convert a UDP socket into a TCP listener",
    );
}
