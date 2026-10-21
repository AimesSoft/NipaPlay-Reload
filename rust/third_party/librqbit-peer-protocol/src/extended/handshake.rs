use std::net::IpAddr;

use buffers::{ByteBuf, ByteBufT};
use librqbit_core::compact_ip::{CompactIpAddr, CompactIpV4, CompactIpV6};
use serde_derive::{Deserialize, Serialize};

use super::PeerExtendedMessageIds;

#[derive(Deserialize, Serialize, Debug, Default, Eq, PartialEq)]
pub struct ExtendedHandshake<ByteBuf: ByteBufT> {
    // NipaPlay patch: BEP 10 makes every key optional; Transmission omits
    // `m` for private torrents, where it offers no extensions.
    #[serde(default)]
    pub m: PeerExtendedMessageIds,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub p: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub v: Option<ByteBuf>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub yourip: Option<CompactIpAddr>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ipv6: Option<CompactIpV6>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ipv4: Option<CompactIpV4>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reqq: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata_size: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub complete_ago: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub upload_only: Option<u32>,
}

impl ExtendedHandshake<ByteBuf<'_>> {
    pub fn new() -> Self {
        Self {
            m: PeerExtendedMessageIds::my(),
            ..Default::default()
        }
    }

    pub fn peer_extended_messages(&self) -> PeerExtendedMessageIds {
        self.m
    }

    pub fn ip_addr(&self) -> Option<IpAddr> {
        if let Some(ref b) = self.ipv4 {
            return Some(b.0.into());
        }
        if let Some(ref b) = self.ipv6 {
            return Some(b.0.into());
        }
        None
    }

    pub fn port(&self) -> Option<u16> {
        self.p.and_then(|p| u16::try_from(p).ok())
    }
}

#[cfg(test)]
mod nipaplay_tests {
    use super::*;

    #[test]
    fn a_handshake_without_m_is_accepted() {
        // Transmission 4.1.3's handshake for a private torrent: no `m`.
        let raw = b"d1:ei1e1:pi51413e4:reqqi2000e11:upload_onlyi1e1:v18:Transmission 4.1.36:yourip4:\x7f\x00\x00\x01e";
        let hs: ExtendedHandshake<ByteBuf> = bencode::from_bytes(raw).unwrap();
        assert_eq!(hs.m, PeerExtendedMessageIds::default());
        assert_eq!(hs.port(), Some(51413));
    }
}
