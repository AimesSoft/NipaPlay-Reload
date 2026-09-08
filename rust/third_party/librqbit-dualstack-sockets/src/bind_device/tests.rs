use std::{net::SocketAddr, time::Duration};

use network_interface::{NetworkInterface, NetworkInterfaceConfig};
use tokio::time::timeout;

use crate::{BindDevice, ConnectOpts, tcp_connect};

pub fn find_localhost_name() -> String {
    let nics = NetworkInterface::show().unwrap();
    nics.into_iter()
        .find(|nic| nic.addr.iter().any(|a| a.ip().is_loopback()))
        .map(|nic| nic.name)
        .expect("expected to find loopback interface")
}

const TIMEOUT: Duration = Duration::from_secs(1);

#[cfg(not(windows))]
#[tokio::test]
async fn test_bind_to_device() {
    let bd_name = find_localhost_name();
    println!("localhost interface name: {bd_name}");
    let bd = BindDevice::new_from_name(&bd_name).expect("expected to create BindDevice");
    println!("bd: {bd:?}");
    let test_addr: SocketAddr = "1.1.1.1:80".parse().unwrap();
    drop(
        timeout(TIMEOUT, tcp_connect(test_addr, ConnectOpts::default()))
            .await
            .expect("unexpected timeout")
            .expect("expected to connect without BD"),
    );

    println!("connected successfully. now will try with bind_device");

    let res = timeout(
        TIMEOUT,
        tcp_connect(
            test_addr,
            ConnectOpts {
                bind_device: Some(&bd),
                ..Default::default()
            },
        ),
    )
    .await;

    #[cfg(target_os = "macos")]
    match &res {
        Ok(Ok(_)) => panic!("expected an error"),
        Ok(Err(e)) => {
            println!("error: {e:#}");
        }
        Err(_) => {
            panic!("unexpected timeout")
        }
    }

    #[cfg(not(target_os = "macos"))]
    match &res {
        Ok(Ok(_)) => panic!("expected an error"),
        Ok(Err(e)) => {
            println!("error: {e:#}");
        }
        Err(_) => {
            println!(
                "timeout, this is expected on linux, as SO_BINDTODEVICE would route the packet via lo"
            )
        }
    }
}
