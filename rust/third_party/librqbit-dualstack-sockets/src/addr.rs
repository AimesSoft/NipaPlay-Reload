use std::net::{Ipv6Addr, SocketAddr, SocketAddrV6};

pub trait TryToV4 {
    fn try_to_ipv4(&self) -> SocketAddr;

    #[cfg(test)]
    fn to_v4(&self) -> SocketAddr {
        let a = self.try_to_ipv4();
        assert!(a.is_ipv4());
        a
    }
}

pub trait ToV6Mapped {
    fn to_ipv6_mapped(&self) -> SocketAddrV6;
}

impl ToV6Mapped for SocketAddr {
    fn to_ipv6_mapped(&self) -> SocketAddrV6 {
        match self {
            SocketAddr::V4(a) => SocketAddrV6::new(a.ip().to_ipv6_mapped(), a.port(), 0, 0),
            SocketAddr::V6(a) => *a,
        }
    }
}

impl TryToV4 for SocketAddr {
    fn try_to_ipv4(&self) -> SocketAddr {
        match self {
            SocketAddr::V4(_) => *self,
            SocketAddr::V6(a) => a.try_to_ipv4(),
        }
    }
}

impl TryToV4 for SocketAddrV6 {
    fn try_to_ipv4(&self) -> SocketAddr {
        self.ip()
            .to_ipv4_mapped()
            .map(|ip| SocketAddr::new(ip.into(), self.port()))
            .unwrap_or(SocketAddr::V6(*self))
    }
}

pub trait WithScopeId {
    fn with_scope_id(&self, scope_id: u32) -> SocketAddrV6;

    fn erase_scope_id(&self) -> SocketAddrV6 {
        self.with_scope_id(0)
    }
}

impl WithScopeId for SocketAddrV6 {
    fn with_scope_id(&self, scope_id: u32) -> SocketAddrV6 {
        let mut addr = *self;
        addr.set_scope_id(scope_id);
        addr
    }
}

pub trait Ipv6AddrExt {
    fn is_link_local_mcast(&self) -> bool;
    fn is_site_local_mcast(&self) -> bool;
}

impl Ipv6AddrExt for Ipv6Addr {
    fn is_link_local_mcast(&self) -> bool {
        const LL: Ipv6Addr = Ipv6Addr::new(0xff02, 0, 0, 0, 0, 0, 0, 0);
        const MASK: Ipv6Addr = Ipv6Addr::new(0xff0f, 0xffff, 0xffff, 0xffff, 0, 0, 0, 0);

        self.to_bits() & MASK.to_bits() == LL.to_bits() & MASK.to_bits()
    }

    fn is_site_local_mcast(&self) -> bool {
        const LL: Ipv6Addr = Ipv6Addr::new(0xff05, 0, 0, 0, 0, 0, 0, 0);
        const MASK: Ipv6Addr = Ipv6Addr::new(0xff0f, 0xffff, 0xffff, 0xffff, 0, 0, 0, 0);

        self.to_bits() & MASK.to_bits() == LL.to_bits() & MASK.to_bits()
    }
}
