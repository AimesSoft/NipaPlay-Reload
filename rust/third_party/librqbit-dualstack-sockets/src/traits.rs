use std::{
    net::SocketAddr,
    task::{Context, Poll},
};

use socket2::SockRef;

pub trait PollSendToVectored {
    fn poll_send_to_vectored(
        &self,
        cx: &mut Context<'_>,
        bufs: &[std::io::IoSlice<'_>],
        target: SocketAddr,
    ) -> Poll<std::io::Result<usize>>;
}

impl PollSendToVectored for tokio::net::UdpSocket {
    fn poll_send_to_vectored(
        &self,
        cx: &mut Context<'_>,
        bufs: &[std::io::IoSlice<'_>],
        target: SocketAddr,
    ) -> Poll<std::io::Result<usize>> {
        let sref = SockRef::from(self);
        loop {
            match sref.send_to_vectored(bufs, &target.into()) {
                Ok(sz) => return Poll::Ready(Ok(sz)),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    std::task::ready!(self.poll_send_ready(cx))?;
                }
                Err(e) => return Poll::Ready(Err(e)),
            }
        }
    }
}

impl PollSendToVectored for crate::UdpSocket {
    fn poll_send_to_vectored(
        &self,
        cx: &mut Context<'_>,
        bufs: &[std::io::IoSlice<'_>],
        target: SocketAddr,
    ) -> Poll<std::io::Result<usize>> {
        let target = self.convert_addr_for_send(target);
        self.socket().poll_send_to_vectored(cx, bufs, target)
    }
}
