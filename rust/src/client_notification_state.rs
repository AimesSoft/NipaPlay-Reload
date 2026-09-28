use std::collections::VecDeque;
use std::sync::{Mutex, OnceLock};

use crate::frb_generated::StreamSink;

use crate::api::client_notifications::ClientNotification;

#[derive(Default)]
struct NotificationState {
    sink: Option<StreamSink<ClientNotification>>,
    pending: VecDeque<ClientNotification>,
}

fn state() -> &'static Mutex<NotificationState> {
    static STATE: OnceLock<Mutex<NotificationState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(NotificationState::default()))
}

pub(crate) fn subscribe(sink: StreamSink<ClientNotification>) {
    let mut state = state()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    state.sink = Some(sink);
    while let Some(notification) = state.pending.pop_front() {
        if let Some(active) = &state.sink {
            if active.add(notification.clone()).is_ok() {
                continue;
            }
        }
        state.sink = None;
        state.pending.push_front(notification);
        break;
    }
}

pub(crate) fn notify(notification: ClientNotification) {
    let mut state = state()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(sink) = &state.sink {
        if sink.add(notification.clone()).is_ok() {
            return;
        }
        state.sink = None;
    }
    if state.pending.len() >= 16 {
        state.pending.pop_front();
    }
    state.pending.push_back(notification);
}
